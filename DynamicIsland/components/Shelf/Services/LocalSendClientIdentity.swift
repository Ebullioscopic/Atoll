/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <https://www.gnu.org/licenses/>.
 */

import CryptoKit
import Foundation
import Security

/// The TLS client identity Atoll presents to LocalSend receivers.
///
/// LocalSend 1.18 receivers in HTTPS mode require mutual TLS: the sender must present a
/// certificate, which only has to be self-signed and currently valid. Without one the
/// receiver drops the handshake and the transfer fails with "The network connection was
/// lost". The official apps also identify themselves by the SHA-256 fingerprint of that
/// certificate, so the same value is sent as `fingerprint`.
///
/// The P-256 private key and the certificate are kept in the login keychain, so the
/// fingerprint stays stable across launches.
final class LocalSendClientIdentity: @unchecked Sendable {
    static let shared = LocalSendClientIdentity()

    struct Loaded {
        let identity: SecIdentity
        let fingerprint: String
    }

    private static let label = "Atoll LocalSend Client"
    private static let keyTag = Data("com.ebullioscopic.atoll.localsend.client-key".utf8)
    private static let validity: TimeInterval = 10 * 365 * 24 * 60 * 60

    private let lock = NSLock()
    private var cached: Loaded?
    private var didFail = false

    private init() {}

    /// The identity if it has been loaded; safe to call from URLSession delegate queues.
    var current: Loaded? {
        lock.lock()
        defer { lock.unlock() }
        return cached
    }

    /// Loads the stored identity, creating it on first use. Does Keychain work, so call off the main thread.
    @discardableResult
    func load() -> Loaded? {
        lock.lock()
        defer { lock.unlock() }
        if let cached { return cached }
        guard !didFail else { return nil }

        let loaded = Self.loadStored() ?? Self.createAndStore()
        if loaded == nil {
            didFail = true
            Logger.log("LocalSend: could not create a TLS client identity; HTTPS receivers may refuse transfers", category: .extensions)
        }
        cached = loaded
        return loaded
    }

    // MARK: Keychain

    private static func loadStored() -> Loaded? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassCertificate,
            kSecAttrLabel as String: label,
            kSecReturnRef as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let item, CFGetTypeID(item) == SecCertificateGetTypeID() else { return nil }
        let certificate = item as! SecCertificate

        // Replace the certificate shortly before it expires; receivers reject expired ones.
        let der = SecCertificateCopyData(certificate) as Data
        if let notAfter = LocalSendCertificateBuilder.notAfter(ofDER: der), notAfter < Date().addingTimeInterval(7 * 24 * 60 * 60) {
            deleteStored()
            return nil
        }

        var identity: SecIdentity?
        guard SecIdentityCreateWithCertificate(nil, certificate, &identity) == errSecSuccess, let identity else {
            deleteStored()
            return nil
        }
        return Loaded(identity: identity, fingerprint: LocalSendCertificateBuilder.fingerprint(ofDER: der))
    }

    private static func createAndStore() -> Loaded? {
        deleteStored()

        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String: 256,
            kSecAttrLabel as String: label,
            kSecPrivateKeyAttrs as String: [
                kSecAttrIsPermanent as String: true,
                kSecAttrApplicationTag as String: keyTag,
                kSecAttrLabel as String: label
            ]
        ]
        var error: Unmanaged<CFError>?
        guard let privateKey = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else {
            Logger.log("LocalSend: key generation failed: \(String(describing: error?.takeRetainedValue()))", category: .extensions)
            return nil
        }

        let now = Date()
        guard let der = LocalSendCertificateBuilder.selfSignedCertificate(
                privateKey: privateKey,
                commonName: "Atoll",
                notBefore: now.addingTimeInterval(-24 * 60 * 60),
                notAfter: now.addingTimeInterval(validity)
              ),
              let certificate = SecCertificateCreateWithData(nil, der as CFData) else {
            deleteStored()
            return nil
        }

        let addStatus = SecItemAdd([
            kSecClass as String: kSecClassCertificate,
            kSecValueRef as String: certificate,
            kSecAttrLabel as String: label
        ] as CFDictionary, nil)
        guard addStatus == errSecSuccess || addStatus == errSecDuplicateItem else {
            Logger.log("LocalSend: storing the client certificate failed (\(addStatus))", category: .extensions)
            deleteStored()
            return nil
        }

        var identity: SecIdentity?
        guard SecIdentityCreateWithCertificate(nil, certificate, &identity) == errSecSuccess, let identity else {
            deleteStored()
            return nil
        }
        return Loaded(identity: identity, fingerprint: LocalSendCertificateBuilder.fingerprint(ofDER: der))
    }

    private static func deleteStored() {
        SecItemDelete([
            kSecClass as String: kSecClassCertificate,
            kSecAttrLabel as String: label
        ] as CFDictionary)
        SecItemDelete([
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: keyTag
        ] as CFDictionary)
    }
}

/// Builds the minimal X.509 v3 certificate LocalSend accepts: self-signed ECDSA P-256 / SHA-256.
enum LocalSendCertificateBuilder {
    private static let ecdsaWithSHA256: [UInt8] = [0x06, 0x08, 0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x04, 0x03, 0x02]
    private static let ecPublicKey: [UInt8] = [0x06, 0x07, 0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x02, 0x01]
    private static let prime256v1: [UInt8] = [0x06, 0x08, 0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x03, 0x01, 0x07]
    private static let commonNameOID: [UInt8] = [0x06, 0x03, 0x55, 0x04, 0x03]

    /// SHA-256 of the DER certificate as uppercase hex, LocalSend's fingerprint format.
    static func fingerprint(ofDER der: Data) -> String {
        SHA256.hash(data: der).map { String(format: "%02X", $0) }.joined()
    }

    static func selfSignedCertificate(privateKey: SecKey, commonName: String, notBefore: Date, notAfter: Date) -> Data? {
        guard let publicKey = SecKeyCopyPublicKey(privateKey),
              let point = SecKeyCopyExternalRepresentation(publicKey, nil) as Data? else { return nil }

        var serial = [UInt8](repeating: 0, count: 16)
        guard SecRandomCopyBytes(kSecRandomDefault, serial.count, &serial) == errSecSuccess else { return nil }
        serial[0] &= 0x7F
        serial[0] |= 0x01

        let name = sequence(set(sequence(commonNameOID + tlv(0x0C, Array(commonName.utf8)))))
        let tbs = sequence(
            tlv(0xA0, integer([0x02])),
            integer(serial),
            sequence(ecdsaWithSHA256),
            name,
            sequence(time(notBefore), time(notAfter)),
            name,
            sequence(sequence(ecPublicKey, prime256v1), bitString(Array(point)))
        )

        guard let signature = SecKeyCreateSignature(privateKey, .ecdsaSignatureMessageX962SHA256, Data(tbs) as CFData, nil) as Data? else {
            return nil
        }
        return Data(sequence(tbs, sequence(ecdsaWithSHA256), bitString(Array(signature))))
    }

    /// Reads `notAfter` back from a certificate this builder produced.
    static func notAfter(ofDER der: Data) -> Date? {
        guard let certificate = SecCertificateCreateWithData(nil, der as CFData),
              let values = SecCertificateCopyValues(certificate, [kSecOIDX509V1ValidityNotAfter] as CFArray, nil) as? [CFString: Any],
              let entry = values[kSecOIDX509V1ValidityNotAfter] as? [CFString: Any],
              let seconds = entry[kSecPropertyKeyValue] as? NSNumber else { return nil }
        return Date(timeIntervalSinceReferenceDate: seconds.doubleValue)
    }

    // MARK: DER

    private static func tlv(_ tag: UInt8, _ content: [UInt8]) -> [UInt8] {
        var length: [UInt8]
        if content.count < 0x80 {
            length = [UInt8(content.count)]
        } else {
            var n = content.count
            var bytes: [UInt8] = []
            while n > 0 {
                bytes.insert(UInt8(n & 0xFF), at: 0)
                n >>= 8
            }
            length = [0x80 | UInt8(bytes.count)] + bytes
        }
        return [tag] + length + content
    }

    private static func sequence(_ parts: [UInt8]...) -> [UInt8] { tlv(0x30, parts.flatMap { $0 }) }
    private static func set(_ content: [UInt8]) -> [UInt8] { tlv(0x31, content) }
    private static func bitString(_ bytes: [UInt8]) -> [UInt8] { tlv(0x03, [0x00] + bytes) }

    private static func integer(_ bytes: [UInt8]) -> [UInt8] {
        var value = Array(bytes.drop { $0 == 0 })
        if value.isEmpty { value = [0] }
        if value[0] & 0x80 != 0 { value.insert(0, at: 0) }
        return tlv(0x02, value)
    }

    /// UTCTime before 2050 and GeneralizedTime from 2050, as RFC 5280 requires.
    private static func time(_ date: Date) -> [UInt8] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy"
        let year = Int(formatter.string(from: date)) ?? 2000
        if year < 2050 {
            formatter.dateFormat = "yyMMddHHmmss'Z'"
            return tlv(0x17, Array(formatter.string(from: date).utf8))
        }
        formatter.dateFormat = "yyyyMMddHHmmss'Z'"
        return tlv(0x18, Array(formatter.string(from: date).utf8))
    }
}
