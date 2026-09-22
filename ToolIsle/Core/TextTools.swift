// Copyright (C) 2026 ToolIsle contributors. SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
public enum TextTools {
    public enum Failure: Error, LocalizedError {
        case oversized, invalidBase64, invalidDate
        public var errorDescription: String? {
            switch self {
            case .oversized: return "输入不能超过 2 MB。"
            case .invalidBase64: return "不是有效的 UTF-8 Base64 文本。"
            case .invalidDate: return "请输入有效时间戳，或带时区的 ISO 8601 日期。"
            }
        }
    }
    private static func checked(_ text: String) throws -> Data {
        let data = Data(text.utf8)
        guard data.count <= 2_000_000 else { throw Failure.oversized }
        return data
    }
    public static func json(_ text: String, pretty: Bool) throws -> String {
        let value = try JSONSerialization.jsonObject(with: checked(text), options: [.fragmentsAllowed])
        let options: JSONSerialization.WritingOptions = pretty ? [.prettyPrinted, .sortedKeys, .fragmentsAllowed] : [.sortedKeys, .fragmentsAllowed]
        return String(decoding: try JSONSerialization.data(withJSONObject: value, options: options), as: UTF8.self)
    }
    public static func base64(_ text: String, decode: Bool) throws -> String {
        let bytes = try checked(text)
        if !decode { return bytes.base64EncodedString() }
        guard let data = Data(base64Encoded: text.filter { !$0.isWhitespace }), let value = String(data: data, encoding: .utf8) else { throw Failure.invalidBase64 }
        return value
    }
    public static func timestamp(_ text: String, milliseconds: Bool) throws -> String {
        guard let value = Double(text.trimmingCharacters(in: .whitespacesAndNewlines)), value.isFinite else { throw Failure.invalidDate }
        let seconds = milliseconds ? value / 1000 : value
        guard seconds >= -62_135_596_800, seconds <= 253_402_300_799 else { throw Failure.invalidDate }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date(timeIntervalSince1970: seconds))
    }
    public static func date(_ text: String) throws -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var date = formatter.date(from: text)
        if date == nil { formatter.formatOptions = [.withInternetDateTime]; date = formatter.date(from: text) }
        guard let date else { throw Failure.invalidDate }
        return "秒：\(Int64(date.timeIntervalSince1970))\n毫秒：\(Int64((date.timeIntervalSince1970 * 1000).rounded()))"
    }
}
