import Foundation

/// Minimal-diff editor for JSON / JSONC config files.
///
/// Unlike `JSONSerialization.data(...) -> write` which rewrites the whole
/// document (losing comments, reordering keys, escaping slashes, dropping
/// trailing newlines), this editor only replaces the text range of the
/// target top-level key's value. Every other byte of the file stays put.
///
/// Used by `ConfigInstaller` to manage the `hooks` / `plugin` entries
/// without disturbing user-authored config around them (issues #105, #106, #119).
enum JSONMinimalEditor {

    // MARK: - Public API

    /// Set (insert or replace) the value of `key` at the top level of `source`.
    ///
    /// - Parameters:
    ///   - source: Original JSON/JSONC text.
    ///   - key: Top-level key to write.
    ///   - value: Any `JSONSerialization`-compatible Swift value (dict, array, string, number, bool, NSNull).
    /// - Returns: New document text, or `nil` if `source` is not a valid JSON *object* at the top level
    ///   (caller MUST NOT overwrite on nil — see #89).
    static func setTopLevelValue(in source: String, key: String, value: Any) -> String? {
        let chars = Array(source)
        guard let doc = parseTopLevelObject(chars: chars) else { return nil }

        let indent = detectKeyIndent(chars: chars, doc: doc)
        guard let serialized = serializeValue(value, keyIndent: indent) else { return nil }

        if let entry = doc.entries.first(where: { $0.key == key }) {
            // Replace value text range only.
            let prefix = String(chars[..<entry.valueStart])
            let suffix = String(chars[entry.valueEnd...])
            return prefix + serialized + suffix
        }
        return insertKey(chars: chars, doc: doc, key: key, serialized: serialized, keyIndent: indent)
    }

    /// Delete a top-level `key` from `source`. Returns `source` unchanged if key missing.
    /// Returns `nil` if `source` is not a valid JSON object at top level.
    static func deleteTopLevelKey(in source: String, key: String) -> String? {
        let chars = Array(source)
        guard let doc = parseTopLevelObject(chars: chars) else { return nil }
        guard let idx = doc.entries.firstIndex(where: { $0.key == key }) else { return source }
        let entry = doc.entries[idx]

        // Compute removal range including adjoining comma.
        var removeStart = entry.keyStart
        var removeEnd = entry.valueEnd

        if doc.entries.count == 1 {
            // Only entry — remove everything between `{` and `}`, leaving an empty object.
            removeStart = doc.objectContentStart
            removeEnd = doc.objectContentEnd
        } else if idx < doc.entries.count - 1 {
            // Not the last entry — extend to trailing comma (+ whitespace/newline up to next entry start).
            let nextStart = doc.entries[idx + 1].keyStart
            // Find the `,` after entry.valueEnd.
            if let commaIdx = findNextNonSpace(chars: chars, from: entry.valueEnd, stopAt: nextStart), chars[commaIdx] == "," {
                removeEnd = commaIdx + 1
                // Also swallow whitespace up to next entry start so the next entry's own indent is preserved.
                while removeEnd < nextStart,
                      chars[removeEnd] == " " || chars[removeEnd] == "\t" {
                    removeEnd += 1
                }
                if removeEnd < nextStart, chars[removeEnd] == "\n" {
                    removeEnd += 1
                }
            }
        } else {
            // Last entry — strip the preceding comma from the previous entry.
            let prev = doc.entries[idx - 1]
            if let commaIdx = findPrevNonSpace(chars: chars, from: entry.keyStart, stopAt: prev.valueEnd),
               chars[commaIdx] == "," {
                removeStart = commaIdx
            } else {
                // No trailing comma (shouldn't happen in valid JSON with >1 entry), keep entry start.
            }
        }

        // Swallow trailing newline after the removed block only if the removed block ends on a line of its own.
        let prefix = String(chars[..<removeStart])
        let suffix = String(chars[removeEnd...])
        return prefix + suffix
    }

    // MARK: - Document model

    private struct Entry {
        let key: String
        let keyStart: Int   // index of opening `"` of the key literal
        let valueStart: Int // index of first char of the value (after `:` and whitespace)
        let valueEnd: Int   // exclusive
    }

    private struct Document {
        let objectContentStart: Int  // index just after the opening `{`
        let objectContentEnd: Int    // index of the matching `}`
        let entries: [Entry]
    }

    // MARK: - Parser

    private static func parseTopLevelObject(chars: [Character]) -> Document? {
        var i = 0
        skipSpace(chars: chars, i: &i)
        guard i < chars.count, chars[i] == "{" else { return nil }
        let openBrace = i
        i += 1

        var entries: [Entry] = []
        var expectEntry = true

        while true {
            skipSpace(chars: chars, i: &i)
            guard i < chars.count else { return nil }
            if chars[i] == "}" {
                let closeBrace = i
                return Document(
                    objectContentStart: openBrace + 1,
                    objectContentEnd: closeBrace,
                    entries: entries
                )
            }
            if !expectEntry {
                return nil // missing comma
            }

            // Parse key
            guard i < chars.count, chars[i] == "\"" else { return nil }
            let keyStart = i
            guard let keyValue = readStringLiteral(chars: chars, i: &i) else { return nil }

            skipSpace(chars: chars, i: &i)
            guard i < chars.count, chars[i] == ":" else { return nil }
            i += 1
            skipSpace(chars: chars, i: &i)

            let valueStart = i
            guard skipValue(chars: chars, i: &i) else { return nil }
            let valueEnd = i

            entries.append(Entry(key: keyValue, keyStart: keyStart, valueStart: valueStart, valueEnd: valueEnd))

            skipSpace(chars: chars, i: &i)
            if i < chars.count, chars[i] == "," {
                i += 1
                expectEntry = true
                continue
            }
            expectEntry = false
        }
    }

    // MARK: - Scanning primitives

    private static func skipSpace(chars: [Character], i: inout Int) {
        while i < chars.count {
            let c = chars[i]
            if c == " " || c == "\t" || c == "\n" || c == "\r" { i += 1; continue }
            if c == "/", i + 1 < chars.count, chars[i + 1] == "/" {
                i += 2
                while i < chars.count && chars[i] != "\n" { i += 1 }
                continue
            }
            if c == "/", i + 1 < chars.count, chars[i + 1] == "*" {
                i += 2
                while i + 1 < chars.count {
                    if chars[i] == "*" && chars[i + 1] == "/" { i += 2; break }
                    i += 1
                }
                continue
            }
            break
        }
    }

    /// Reads a JSON string literal starting at `i`, returns the parsed value and advances `i` past the closing `"`.
    private static func readStringLiteral(chars: [Character], i: inout Int) -> String? {
        guard i < chars.count, chars[i] == "\"" else { return nil }
        i += 1
        var out = ""
        while i < chars.count {
            let c = chars[i]
            if c == "\\" {
                guard i + 1 < chars.count else { return nil }
                let esc = chars[i + 1]
                switch esc {
                case "\"": out.append("\"")
                case "\\": out.append("\\")
                case "/":  out.append("/")
                case "b":  out.append("\u{08}")
                case "f":  out.append("\u{0C}")
                case "n":  out.append("\n")
                case "r":  out.append("\r")
                case "t":  out.append("\t")
                case "u":
                    guard i + 5 < chars.count else { return nil }
                    let hex = String(chars[(i + 2)...(i + 5)])
                    guard let code = UInt32(hex, radix: 16), let scalar = UnicodeScalar(code) else { return nil }
                    out.append(Character(scalar))
                    i += 6
                    continue
                default: out.append(esc)
                }
                i += 2
                continue
            }
            if c == "\"" { i += 1; return out }
            out.append(c)
            i += 1
        }
        return nil
    }

    /// Advances `i` past a JSON value. Does not parse — only skips to the end.
    private static func skipValue(chars: [Character], i: inout Int) -> Bool {
        skipSpace(chars: chars, i: &i)
        guard i < chars.count else { return false }
        let c = chars[i]
        switch c {
        case "\"":
            return readStringLiteral(chars: chars, i: &i) != nil
        case "{":
            return skipObjectOrArray(chars: chars, i: &i, open: "{", close: "}")
        case "[":
            return skipObjectOrArray(chars: chars, i: &i, open: "[", close: "]")
        case "t", "f", "n":
            while i < chars.count, chars[i].isLetter { i += 1 }
            return true
        case "-", "+", "0", "1", "2", "3", "4", "5", "6", "7", "8", "9":
            while i < chars.count {
                let cc = chars[i]
                if cc.isNumber || cc == "." || cc == "e" || cc == "E" || cc == "-" || cc == "+" {
                    i += 1
                } else { break }
            }
            return true
        default:
            return false
        }
    }

    private static func skipObjectOrArray(chars: [Character], i: inout Int, open: Character, close: Character) -> Bool {
        guard i < chars.count, chars[i] == open else { return false }
        i += 1
        var depth = 1
        while i < chars.count, depth > 0 {
            let c = chars[i]
            if c == "\"" {
                if readStringLiteral(chars: chars, i: &i) == nil { return false }
                continue
            }
            if c == "/", i + 1 < chars.count, (chars[i + 1] == "/" || chars[i + 1] == "*") {
                skipSpace(chars: chars, i: &i)
                continue
            }
            if c == open || c == "{" || c == "[" { depth += 1 }
            else if c == close || c == "}" || c == "]" {
                // Generic `{`/`[` -> `}`/`]` matching is sloppy for mixed nesting, but JSON
                // nesting is well-formed so we rely on each opener pairing with its own closer.
                depth -= 1
                if depth == 0 { i += 1; return true }
            }
            i += 1
        }
        return depth == 0
    }

    private static func findNextNonSpace(chars: [Character], from: Int, stopAt: Int) -> Int? {
        var i = from
        while i < stopAt {
            let c = chars[i]
            if c == " " || c == "\t" || c == "\n" || c == "\r" { i += 1; continue }
            if c == "/", i + 1 < stopAt, chars[i + 1] == "/" {
                i += 2
                while i < stopAt && chars[i] != "\n" { i += 1 }
                continue
            }
            if c == "/", i + 1 < stopAt, chars[i + 1] == "*" {
                i += 2
                while i + 1 < stopAt {
                    if chars[i] == "*" && chars[i + 1] == "/" { i += 2; break }
                    i += 1
                }
                continue
            }
            return i
        }
        return nil
    }

    private static func findPrevNonSpace(chars: [Character], from: Int, stopAt: Int) -> Int? {
        var i = from - 1
        while i >= stopAt {
            let c = chars[i]
            if c == " " || c == "\t" || c == "\n" || c == "\r" { i -= 1; continue }
            return i
        }
        return nil
    }

    // MARK: - Indent detection

    private static func detectKeyIndent(chars: [Character], doc: Document) -> String {
        // Prefer the indent of the first entry.
        if let first = doc.entries.first {
            var start = first.keyStart
            while start > 0 && chars[start - 1] != "\n" { start -= 1 }
            let prefix = chars[start..<first.keyStart]
            if prefix.allSatisfy({ $0 == " " || $0 == "\t" }) {
                return String(prefix)
            }
        }
        // Fallback: indent of closing `}` + 2 spaces.
        var start = doc.objectContentEnd
        while start > 0 && chars[start - 1] != "\n" { start -= 1 }
        let prefix = chars[start..<doc.objectContentEnd]
        if prefix.allSatisfy({ $0 == " " || $0 == "\t" }) {
            return String(prefix) + "  "
        }
        return "  "
    }

    private static func closingBraceIndent(chars: [Character], doc: Document) -> String {
        var start = doc.objectContentEnd
        while start > 0 && chars[start - 1] != "\n" { start -= 1 }
        let prefix = chars[start..<doc.objectContentEnd]
        if prefix.allSatisfy({ $0 == " " || $0 == "\t" }) {
            return String(prefix)
        }
        return ""
    }

    // MARK: - Insertion

    private static func insertKey(chars: [Character], doc: Document, key: String, serialized: String, keyIndent: String) -> String? {
        let closingIndent = closingBraceIndent(chars: chars, doc: doc)
        let entry = "\"\(escape(key))\": \(serialized)"

        if doc.entries.isEmpty {
            // `{}` or `{   }` -> replace content with a single entry.
            let prefix = String(chars[...(doc.objectContentStart - 1)])
            let suffix = String(chars[doc.objectContentEnd...])
            return prefix + "\n\(keyIndent)\(entry)\n\(closingIndent)" + suffix
        }

        // Append after the last entry's value, before the closing `}`.
        let last = doc.entries.last!
        // Everything from last.valueEnd up to doc.objectContentEnd (the `}`) is whitespace/comments.
        // Insert `,\n<indent><entry>` right after last.valueEnd, keeping the trailing whitespace intact.
        let insertPoint = last.valueEnd
        let prefix = String(chars[..<insertPoint])
        let suffix = String(chars[insertPoint...])
        // Determine the newline style: does the existing content between last entry and `}` contain a newline?
        let tail = chars[last.valueEnd..<doc.objectContentEnd]
        let hasNewline = tail.contains("\n")
        let inserted = hasNewline ? ",\n\(keyIndent)\(entry)" : ",\n\(keyIndent)\(entry)\n\(closingIndent)"
        if !hasNewline {
            // Need to also strip trailing spaces in `suffix` before the `}` so the closing brace sits on its own line.
            // But to keep behavior minimal, insert with explicit newlines regardless.
            return prefix + inserted + suffix
        }
        return prefix + inserted + suffix
    }

    private static func escape(_ s: String) -> String {
        var out = ""
        for c in s {
            switch c {
            case "\"": out.append("\\\"")
            case "\\": out.append("\\\\")
            case "\n": out.append("\\n")
            case "\r": out.append("\\r")
            case "\t": out.append("\\t")
            case "\u{08}": out.append("\\b")
            case "\u{0C}": out.append("\\f")
            default: out.append(c)
            }
        }
        return out
    }

    // MARK: - Value serialization

    /// Serialize a Swift value to JSON text suitable for embedding at an indented position.
    /// - Parameter keyIndent: The indentation of the key's own line; nested lines get the same prefix.
    /// - Returns: JSON text ready to be placed after `"key": `, or `nil` if the value cannot be serialized.
    ///
    /// Intentionally omits `.sortedKeys` so NSDictionary iteration order is preserved (unstable for dicts we
    /// constructed ourselves, but stable enough to not force alphabetical reordering of user-adjacent data).
    static func serializeValue(_ value: Any, keyIndent: String) -> String? {
        if JSONSerialization.isValidJSONObject(value) {
            let opts: JSONSerialization.WritingOptions = [.prettyPrinted, .withoutEscapingSlashes]
            guard let data = try? JSONSerialization.data(withJSONObject: value, options: opts),
                  let raw = String(data: data, encoding: .utf8) else { return nil }
            return reindent(raw, keyIndent: keyIndent)
        }
        return serializePrimitive(value)
    }

    private static func serializePrimitive(_ value: Any) -> String? {
        // JSONSerialization's top-level must be object/array; wrap in `[value]` and strip outer brackets.
        guard let data = try? JSONSerialization.data(withJSONObject: [value], options: [.withoutEscapingSlashes]),
              var raw = String(data: data, encoding: .utf8) else { return nil }
        raw = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard raw.hasPrefix("["), raw.hasSuffix("]") else { return nil }
        raw.removeFirst()
        raw.removeLast()
        return raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Re-indent a pretty-printed JSON string so its leading edge aligns with the containing key's indent.
    /// `raw` starts with 0-indent (as produced by JSONSerialization). We prepend `keyIndent` to every line
    /// *except* the first, so the value lines up inside its parent object.
    private static func reindent(_ raw: String, keyIndent: String) -> String {
        var lines = raw.components(separatedBy: "\n")
        guard lines.count > 1 else { return raw }
        for idx in 1..<lines.count {
            if !lines[idx].isEmpty {
                lines[idx] = keyIndent + lines[idx]
            }
        }
        return lines.joined(separator: "\n")
    }
}
