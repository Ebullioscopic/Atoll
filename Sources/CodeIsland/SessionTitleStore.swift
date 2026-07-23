import Foundation
import CodeIslandCore

struct ResolvedSessionTitle: Sendable, Equatable {
    let title: String
    let source: SessionTitleSource
}

enum SessionTitleStore {
    static func supports(provider: String) -> Bool {
        switch provider {
        case "codex", "claude":
            return true
        default:
            return false
        }
    }

    static func title(for sessionId: String, provider: String, cwd: String? = nil) -> ResolvedSessionTitle? {
        switch provider {
        case "codex":
            guard let title = codexThreadName(sessionId: sessionId) else { return nil }
            return ResolvedSessionTitle(title: title, source: .codexThreadName)
        case "claude":
            return claudeTitle(sessionId: sessionId, cwd: cwd)
        default:
            return nil
        }
    }

    static func codexThreadName(sessionId: String) -> String? {
        let path = NSHomeDirectory() + "/.codex/session_index.jsonl"
        guard let contents = try? String(contentsOfFile: path, encoding: .utf8) else {
            return nil
        }
        return try? codexThreadName(sessionId: sessionId, indexContents: contents)
    }

    static func codexThreadName(sessionId: String, indexContents: String) throws -> String? {
        struct Entry: Decodable {
            let id: String
            let thread_name: String?
            let updated_at: String?
        }

        let decoder = JSONDecoder()
        let iso8601 = ISO8601DateFormatter()
        var latestMatch: (updatedAt: Date, title: String)?

        for line in indexContents.split(whereSeparator: \.isNewline) {
            guard let data = String(line).data(using: .utf8),
                  let entry = try? decoder.decode(Entry.self, from: data),
                  entry.id == sessionId,
                  let rawTitle = entry.thread_name?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !rawTitle.isEmpty
            else {
                continue
            }

            let updatedAt = entry.updated_at.flatMap(iso8601.date(from:)) ?? .distantPast
            if let latestMatch, latestMatch.updatedAt > updatedAt {
                continue
            }

            latestMatch = (updatedAt, rawTitle)
        }

        return latestMatch?.title
    }

    static func claudeTitle(sessionId: String, cwd: String?) -> ResolvedSessionTitle? {
        guard let cwd else { return nil }

        let projectDir = cwd.claudeProjectDirEncoded()
        let path = "\(ClaudeConfigPaths.projectsDir())/\(projectDir)/\(sessionId).jsonl"

        guard let handle = FileHandle(forReadingAtPath: path) else {
            return nil
        }
        defer { handle.closeFile() }

        let fileSize = handle.seekToEndOfFile()
        let readSize: UInt64 = min(fileSize, 65536)

        handle.seek(toFileOffset: 0)
        let headData = handle.readData(ofLength: Int(readSize))

        let tailData: Data
        if fileSize > readSize {
            handle.seek(toFileOffset: fileSize - readSize)
            tailData = handle.readDataToEndOfFile()
        } else {
            tailData = headData
        }

        guard let head = String(data: headData, encoding: .utf8),
              let tail = String(data: tailData, encoding: .utf8)
        else {
            return nil
        }

        let tailTitles = latestClaudeTitles(in: tail)
        let headTitles = latestClaudeTitles(in: head)

        if let customTitle = tailTitles.custom ?? headTitles.custom {
            return ResolvedSessionTitle(title: customTitle, source: .claudeCustomTitle)
        }
        if let aiTitle = tailTitles.ai ?? headTitles.ai {
            return ResolvedSessionTitle(title: aiTitle, source: .claudeAiTitle)
        }
        return nil
    }

    private static func latestClaudeTitles(in contents: String) -> (custom: String?, ai: String?) {
        var latestCustomTitle: String?
        var latestAiTitle: String?

        for line in contents.split(whereSeparator: \.isNewline) {
            guard let data = String(line).data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = json["type"] as? String
            else {
                continue
            }

            switch type {
            case "custom-title":
                if let title = trimmedTitle(json["customTitle"]) {
                    latestCustomTitle = title
                }
            case "ai-title":
                if let title = trimmedTitle(json["aiTitle"]) {
                    latestAiTitle = title
                }
            default:
                continue
            }
        }

        return (latestCustomTitle, latestAiTitle)
    }

    private static func trimmedTitle(_ value: Any?) -> String? {
        guard let raw = value as? String else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
