import Foundation

public enum PreviewSanitizer {
    public static func sanitize(_ value: String?, maxLength: Int = 60) -> String? {
        guard let value, !value.isEmpty, maxLength > 0 else { return nil }
        var result = value.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        result = replace(pattern: "(?i)\\bBearer\\s+[A-Za-z0-9._~+\\-/=]+", in: result)
        result = replace(
            pattern: "(?i)\\b(api[_-]?key|token|password|secret)\\s*[:=]\\s*[^\\s,;，；]+",
            in: result
        )
        result = result.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty else { return nil }
        return String(result.prefix(maxLength))
    }

    private static func replace(pattern: String, in value: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return value }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        return regex.stringByReplacingMatches(in: value, range: range, withTemplate: "[REDACTED]")
    }
}
