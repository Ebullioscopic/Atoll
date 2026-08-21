import Foundation

enum CodexThreadActionResolver {
    static let metadataPrefix = "atoll.openCodexThread."

    static func sectionURL(
        sectionID: String?,
        elementCount: Int,
        metadata: [String: String]
    ) -> URL? {
        guard elementCount == 1 else { return nil }
        return url(sectionID: sectionID, elementIndex: 0, metadata: metadata)
    }

    static func url(
        sectionID: String?,
        elementIndex: Int,
        metadata: [String: String]
    ) -> URL? {
        guard let sectionID,
              !sectionID.isEmpty,
              elementIndex >= 0,
              let rawURL = metadata["\(metadataPrefix)\(sectionID).\(elementIndex)"],
              let url = URL(string: rawURL),
              isCodexThreadURL(url) else {
            return nil
        }
        return url
    }

    static func isCodexThreadURL(_ url: URL) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == "codex",
              components.host?.lowercased() == "threads" else {
            return false
        }

        let threadID = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return !threadID.isEmpty && !threadID.contains("/")
    }
}
