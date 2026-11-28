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

import Security
import XCTest

@testable import Atoll

/// LocalSend 1.18 receivers in HTTPS mode only accept senders that present a valid
/// self-signed certificate, and identify them by its SHA-256 fingerprint (#815).
final class LocalSendClientIdentityTests: XCTestCase {
    private func makeKey() throws -> SecKey {
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String: 256
        ]
        return try XCTUnwrap(SecKeyCreateRandomKey(attributes as CFDictionary, nil))
    }

    func testBuildsAParsableCertificateForTheKey() throws {
        let key = try makeKey()
        let notAfter = Date(timeIntervalSinceReferenceDate: 1_000_000_000)
        let der = try XCTUnwrap(LocalSendCertificateBuilder.selfSignedCertificate(
            privateKey: key, commonName: "Atoll", notBefore: notAfter.addingTimeInterval(-86_400), notAfter: notAfter
        ))

        let certificate = try XCTUnwrap(SecCertificateCreateWithData(nil, der as CFData))
        XCTAssertEqual(SecCertificateCopySubjectSummary(certificate) as String?, "Atoll")
        let certificateKey = try XCTUnwrap(SecCertificateCopyKey(certificate))
        XCTAssertEqual(
            SecKeyCopyExternalRepresentation(certificateKey, nil) as Data?,
            SecKeyCopyExternalRepresentation(try XCTUnwrap(SecKeyCopyPublicKey(key)), nil) as Data?
        )
        let readBack = try XCTUnwrap(LocalSendCertificateBuilder.notAfter(ofDER: der))
        XCTAssertEqual(readBack.timeIntervalSinceReferenceDate, notAfter.timeIntervalSinceReferenceDate, accuracy: 1)
    }

    func testUsesGeneralizedTimeFrom2050() throws {
        let notAfter = try XCTUnwrap(ISO8601DateFormatter().date(from: "2051-06-01T00:00:00Z"))
        let der = try XCTUnwrap(LocalSendCertificateBuilder.selfSignedCertificate(
            privateKey: try makeKey(), commonName: "Atoll", notBefore: Date(), notAfter: notAfter
        ))
        let readBack = try XCTUnwrap(LocalSendCertificateBuilder.notAfter(ofDER: der))
        XCTAssertEqual(readBack.timeIntervalSince1970, notAfter.timeIntervalSince1970, accuracy: 1)
    }

    func testFingerprintIsUppercaseSHA256Hex() {
        XCTAssertEqual(
            LocalSendCertificateBuilder.fingerprint(ofDER: Data("abc".utf8)),
            "BA7816BF8F01CFEA414140DE5DAE2223B00361A396177A9CB410FF61F20015AD"
        )
    }
}
