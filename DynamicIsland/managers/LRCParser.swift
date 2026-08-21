/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

import Foundation

/// Parser for the LRC lyrics format.
enum LRCParser {

    /// Matches one `[mm:ss]`, `[mm:ss.xx]` or `[mm:ss.xxx]` tag.
    ///
    /// The fractional part is one to three digits and is scaled by its own
    /// length: `.5` is five tenths, `.50` is fifty hundredths and `.500` is five
    /// hundred thousandths, and all three mean half a second.
    private static let timeTagPattern = "\\[(\\d{1,3}):(\\d{2})(?:[.:](\\d{1,3}))?\\]"

    /// Matches the `[offset:±ms]` metadata tag, which shifts every line.
    /// A positive offset means the lyrics should appear earlier.
    private static let offsetTagPattern = "\\[offset:\\s*([+-]?\\d+)\\s*\\]"

    static func parse(_ lrc: String) -> [LyricLine] {
        guard let timeRegex = try? NSRegularExpression(pattern: timeTagPattern) else { return [] }

        let offset = parseOffset(lrc)
        var lyrics: [LyricLine] = []

        for line in lrc.components(separatedBy: .newlines) {
            let nsLine = line as NSString
            let fullRange = NSRange(location: 0, length: nsLine.length)
            let matches = timeRegex.matches(in: line, range: fullRange)
            guard !matches.isEmpty else { continue }

            // A line may carry several timestamps -- a repeated chorus is written
            // once with one tag per repetition. The text starts after the last of
            // them, and the line is emitted at every timestamp it carries.
            guard let lastMatch = matches.last else { continue }
            let textStart = lastMatch.range.location + lastMatch.range.length
            guard textStart <= nsLine.length else { continue }

            let text = nsLine.substring(from: textStart).trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { continue }

            for match in matches {
                guard let timestamp = timestamp(from: match, in: nsLine) else { continue }
                lyrics.append(LyricLine(timestamp: max(0, timestamp - offset), text: text))
            }
        }

        return lyrics.sorted { $0.timestamp < $1.timestamp }
    }

    /// Reads the `[offset:±ms]` tag, in seconds. Returns 0 when absent.
    private static func parseOffset(_ lrc: String) -> TimeInterval {
        guard let regex = try? NSRegularExpression(pattern: offsetTagPattern) else { return 0 }
        let nsLRC = lrc as NSString
        let range = NSRange(location: 0, length: nsLRC.length)
        guard let match = regex.firstMatch(in: lrc, range: range),
              match.range(at: 1).location != NSNotFound,
              let milliseconds = Double(nsLRC.substring(with: match.range(at: 1)))
        else { return 0 }
        return milliseconds / 1000
    }

    private static func timestamp(from match: NSTextCheckingResult, in line: NSString) -> TimeInterval? {
        let minuteRange = match.range(at: 1)
        let secondRange = match.range(at: 2)
        guard minuteRange.location != NSNotFound, secondRange.location != NSNotFound,
              let minutes = Double(line.substring(with: minuteRange)),
              let seconds = Double(line.substring(with: secondRange))
        else { return nil }

        var fraction: TimeInterval = 0
        let fractionRange = match.range(at: 3)
        if fractionRange.location != NSNotFound {
            let digits = line.substring(with: fractionRange)
            if let value = Double(digits) {
                // Scale by the number of digits written, so ".5" is not read as
                // five hundredths of a second.
                fraction = value / pow(10, Double(digits.count))
            }
        }

        return minutes * 60 + seconds + fraction
    }
}
