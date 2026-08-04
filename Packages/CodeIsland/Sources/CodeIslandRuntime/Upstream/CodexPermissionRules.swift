import Foundation
import CodeIslandCore

struct CodexPermissionRules {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    static func isCodexEvent(_ event: HookEvent) -> Bool {
        SessionSnapshot.normalizedSupportedSource(event.rawJSON["_source"] as? String) == "codex"
    }

    static func shouldDeferToCodexAutoReview(for event: HookEvent, fileManager: FileManager = .default) -> Bool {
        guard isCodexEvent(event) else { return false }

        if let reviewer = eventReviewerValue(event.rawJSON) {
            return isAutoReviewReviewer(reviewer)
        }

        let configPath = ConfigInstaller.codexHome() + "/config.toml"
        guard fileManager.fileExists(atPath: configPath),
              let contents = try? String(contentsOfFile: configPath, encoding: .utf8) else {
            return false
        }
        return configEnablesAutoReview(contents)
    }

    static func configEnablesAutoReview(_ contents: String) -> Bool {
        var currentSection: String?
        var selectedProfile: String?
        var topLevelReviewer: String?
        var profileReviewers: [String: String] = [:]

        for rawLine in contents.components(separatedBy: .newlines) {
            let line = stripTomlComment(rawLine).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }

            if let section = tomlTableName(from: line) {
                currentSection = section
                continue
            }

            guard let equals = line.firstIndex(of: "=") else { continue }
            let key = String(line[..<equals]).trimmingCharacters(in: .whitespacesAndNewlines)
            let value = tomlScalarString(String(line[line.index(after: equals)...]))

            if currentSection == nil {
                if key == "profile" {
                    selectedProfile = value
                } else if key == "approvals_reviewer" {
                    topLevelReviewer = value
                }
            } else if let profileName = profileName(fromSection: currentSection),
                      key == "approvals_reviewer" {
                profileReviewers[profileName] = value
            }
        }

        if let selectedProfile,
           let profileReviewer = profileReviewers[selectedProfile] {
            return isAutoReviewReviewer(profileReviewer)
        }

        if let topLevelReviewer {
            return isAutoReviewReviewer(topLevelReviewer)
        }

        return false
    }

    static func prefixPattern(for event: HookEvent) -> [String]? {
        if let suggested = findSuggestedPrefixRule(in: event.rawJSON) {
            return suggested
        }

        guard event.toolName == "Bash",
              let command = event.toolInput?["command"] as? String else {
            return nil
        }

        return shellPrefix(from: command, maxTokens: 3)
    }

    @discardableResult
    func persistAlwaysAllowRule(for event: HookEvent) -> Bool {
        if let mcpTool = Self.mcpToolApprovalTarget(for: event) {
            return persistMCPToolApproval(serverID: mcpTool.serverID, toolName: mcpTool.toolName)
        }

        guard let pattern = Self.prefixPattern(for: event), !pattern.isEmpty else {
            return false
        }

        let rulesDirectory = ConfigInstaller.codexHome() + "/rules"
        let rulesPath = rulesDirectory + "/codeisland.rules"
        let block = Self.ruleBlock(for: pattern)
        let patternLine = Self.patternLine(for: pattern)

        do {
            try fileManager.createDirectory(atPath: rulesDirectory, withIntermediateDirectories: true)

            let existing = (try? String(contentsOfFile: rulesPath, encoding: .utf8)) ?? ""
            if existing.contains(patternLine), existing.contains(#"decision = "allow""#) {
                return true
            }

            let separator = existing.isEmpty || existing.hasSuffix("\n") ? "" : "\n"
            let updated = existing + separator + block
            try updated.write(toFile: rulesPath, atomically: true, encoding: .utf8)
            return true
        } catch {
            return false
        }
    }

    private func persistMCPToolApproval(serverID: String, toolName: String) -> Bool {
        let configPath = ConfigInstaller.codexHome() + "/config.toml"
        let configDirectory = (configPath as NSString).deletingLastPathComponent
        let targetPath = ["mcp_servers", serverID, "tools", toolName]

        do {
            try fileManager.createDirectory(atPath: configDirectory, withIntermediateDirectories: true)
            let existing = (try? String(contentsOfFile: configPath, encoding: .utf8)) ?? ""
            let updated = Self.configWithMCPToolApproval(
                existing,
                tablePath: targetPath,
                comment: #"Added by CodeIsland when "Always Allow" is clicked for a Codex MCP tool."#
            )
            try updated.write(toFile: configPath, atomically: true, encoding: .utf8)
            return true
        } catch {
            return false
        }
    }

    static func mcpToolApprovalTarget(for event: HookEvent) -> (serverID: String, toolName: String)? {
        guard isCodexEvent(event),
              let rawToolName = event.toolName,
              rawToolName.hasPrefix("mcp__") else {
            return nil
        }

        let rest = String(rawToolName.dropFirst("mcp__".count))
        guard let separator = rest.range(of: "__") else { return nil }
        let serverID = String(rest[..<separator.lowerBound])
        let toolName = String(rest[separator.upperBound...])
        guard !serverID.isEmpty, !toolName.isEmpty else { return nil }
        return (serverID, toolName)
    }

    static func configWithMCPToolApproval(_ contents: String, tablePath: [String], comment: String) -> String {
        var lines = contents.components(separatedBy: .newlines)
        if contents.hasSuffix("\n") {
            lines.removeLast()
        }

        if let headerIndex = lines.firstIndex(where: { tomlTableSegments(from: $0) == tablePath }) {
            let endIndex = lines[(headerIndex + 1)...].firstIndex(where: { tomlTableSegments(from: $0) != nil })
                ?? lines.endIndex
            if let approvalIndex = lines[(headerIndex + 1)..<endIndex].firstIndex(where: { tomlKey(from: $0) == "approval_mode" }) {
                lines[approvalIndex] = #"approval_mode = "approve""#
            } else {
                lines.insert(#"approval_mode = "approve""#, at: headerIndex + 1)
            }
        } else {
            if !lines.isEmpty, lines.last?.isEmpty == false {
                lines.append("")
            }
            lines.append("# \(comment)")
            lines.append("[\(tablePath.map(tomlKeySegment).joined(separator: "."))]")
            lines.append(#"approval_mode = "approve""#)
        }

        return lines.joined(separator: "\n") + "\n"
    }

    private static func patternLine(for pattern: [String]) -> String {
        "pattern = [\(pattern.map(quotedRuleString).joined(separator: ", "))]"
    }

    private static func ruleBlock(for pattern: [String]) -> String {
        """
        # Added by CodeIsland when "Always Allow" is clicked for Codex.
        prefix_rule(
            \(patternLine(for: pattern)),
            decision = "allow",
            justification = "Allowed from CodeIsland Always Allow",
        )

        """
    }

    private static func quotedRuleString(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
        return "\"\(escaped)\""
    }

    private static func eventReviewerValue(_ rawJSON: [String: Any]) -> String? {
        for key in ["approvals_reviewer", "approvalsReviewer", "_approvals_reviewer"] {
            if let value = rawJSON[key] as? String {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            }
        }
        return nil
    }

    private static func isAutoReviewReviewer(_ value: String) -> Bool {
        let normalized = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            .lowercased()
        return normalized == "auto_review" || normalized == "guardian_subagent"
    }

    private static func stripTomlComment(_ line: String) -> String {
        var result = ""
        var quote: Character?
        var escaping = false

        for ch in line {
            if let activeQuote = quote {
                result.append(ch)
                if escaping {
                    escaping = false
                } else if activeQuote == "\"", ch == "\\" {
                    escaping = true
                } else if ch == activeQuote {
                    quote = nil
                }
                continue
            }

            if ch == "#" {
                break
            }
            if ch == "\"" || ch == "'" {
                quote = ch
            }
            result.append(ch)
        }

        return result
    }

    private static func tomlTableName(from line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("["),
              trimmed.hasSuffix("]"),
              !trimmed.hasPrefix("[[") else {
            return nil
        }
        return String(trimmed.dropFirst().dropLast())
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func profileName(fromSection section: String?) -> String? {
        guard let section, section.hasPrefix("profiles.") else { return nil }
        let raw = String(section.dropFirst("profiles.".count))
        let name = tomlScalarString(raw)
        return name.isEmpty ? nil : name
    }

    private static func tomlScalarString(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2,
              let first = trimmed.first,
              let last = trimmed.last,
              (first == "\"" || first == "'"),
              first == last else {
            return trimmed
        }

        return String(trimmed.dropFirst().dropLast())
    }

    private static func tomlKey(from line: String) -> String? {
        let stripped = stripTomlComment(line).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let equals = stripped.firstIndex(of: "=") else { return nil }
        return String(stripped[..<equals]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func tomlTableSegments(from line: String) -> [String]? {
        let trimmed = stripTomlComment(line).trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("["),
              trimmed.hasSuffix("]"),
              !trimmed.hasPrefix("[[") else {
            return nil
        }

        let body = String(trimmed.dropFirst().dropLast())
        var segments: [String] = []
        var current = ""
        var quote: Character?
        var escaping = false

        func appendSegment() {
            let segment = current.trimmingCharacters(in: .whitespacesAndNewlines)
            if !segment.isEmpty {
                segments.append(segment)
            }
            current = ""
        }

        for ch in body {
            if let activeQuote = quote {
                if escaping {
                    current.append(ch)
                    escaping = false
                } else if activeQuote == "\"", ch == "\\" {
                    escaping = true
                } else if ch == activeQuote {
                    quote = nil
                } else {
                    current.append(ch)
                }
                continue
            }

            if ch == "\"" || ch == "'" {
                quote = ch
            } else if ch == "." {
                appendSegment()
            } else {
                current.append(ch)
            }
        }
        appendSegment()
        return segments.isEmpty ? nil : segments
    }

    private static func tomlKeySegment(_ value: String) -> String {
        if value.range(of: #"^[A-Za-z0-9_-]+$"#, options: .regularExpression) != nil {
            return value
        }
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    private static func findSuggestedPrefixRule(in value: Any) -> [String]? {
        if let dictionary = value as? [String: Any] {
            for key in ["prefix_rule", "prefixRule"] {
                if let pattern = stringArray(from: dictionary[key]) {
                    return pattern
                }
            }

            for nested in dictionary.values {
                if let pattern = findSuggestedPrefixRule(in: nested) {
                    return pattern
                }
            }
        } else if let array = value as? [Any] {
            for nested in array {
                if let pattern = findSuggestedPrefixRule(in: nested) {
                    return pattern
                }
            }
        }
        return nil
    }

    private static func stringArray(from value: Any?) -> [String]? {
        if let pattern = value as? [String], !pattern.isEmpty {
            return pattern
        }
        if let dictionary = value as? [String: Any],
           let pattern = dictionary["pattern"] as? [String],
           !pattern.isEmpty {
            return pattern
        }
        return nil
    }

    private static func shellPrefix(from command: String, maxTokens: Int) -> [String]? {
        var tokens: [String] = []
        var current = ""
        var quote: Character?
        var escaping = false
        var index = command.startIndex

        func appendCurrentToken() {
            guard !current.isEmpty else { return }
            tokens.append(current)
            current = ""
        }

        while index < command.endIndex {
            let char = command[index]
            let next = command.index(after: index)

            if escaping {
                current.append(char)
                escaping = false
                index = next
                continue
            }

            if char == "\\" {
                escaping = true
                index = next
                continue
            }

            if let activeQuote = quote {
                if char == activeQuote {
                    quote = nil
                } else {
                    current.append(char)
                }
                index = next
                continue
            }

            if char == "'" || char == "\"" {
                quote = char
                index = next
                continue
            }

            if char == "$", next < command.endIndex, command[next] == "(" {
                appendCurrentToken()
                break
            }

            if char == "\n" || char == "|" || char == ";" || char == "<" || char == ">" || char == "&" {
                appendCurrentToken()
                break
            }

            if char.isWhitespace {
                appendCurrentToken()
                if tokens.count >= maxTokens {
                    break
                }
            } else {
                current.append(char)
            }

            index = next
        }

        appendCurrentToken()

        let prefix = Array(tokens.prefix(maxTokens))
        guard !prefix.isEmpty, !looksLikeEnvironmentAssignment(prefix[0]) else {
            return nil
        }
        return prefix
    }

    private static func looksLikeEnvironmentAssignment(_ token: String) -> Bool {
        guard let equalsIndex = token.firstIndex(of: "="), equalsIndex != token.startIndex else {
            return false
        }
        let name = token[..<equalsIndex]
        return name.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" }
    }
}
