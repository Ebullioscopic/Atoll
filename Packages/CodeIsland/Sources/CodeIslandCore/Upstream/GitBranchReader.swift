import Foundation

/// Checked-out branch info for a session's cwd.
public struct GitBranchInfo: Equatable, Sendable {
    public let branch: String
    public let isWorktree: Bool

    public init(branch: String, isWorktree: Bool) {
        self.branch = branch
        self.isWorktree = isWorktree
    }
}

/// Resolves the checked-out git branch by reading `.git` metadata directly —
/// never spawns a git process (sessions fire hooks many times a minute, and
/// cwd may be under sandbox-restricted paths where subprocesses are costly).
public enum GitBranchReader {
    /// Walk up from `cwd` to the nearest `.git` entry (a directory for a
    /// primary checkout, a `gitdir:` pointer file for linked worktrees and
    /// submodules) and resolve HEAD. Depth-capped so a bogus cwd never scans
    /// the whole filesystem upward.
    public static func read(cwd: String) -> GitBranchInfo? {
        var dir = (cwd as NSString).standardizingPath
        let fm = FileManager.default
        for _ in 0..<12 {
            let gitPath = dir + "/.git"
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: gitPath, isDirectory: &isDir) {
                if isDir.boolValue {
                    return headInfo(gitDir: gitPath, isWorktree: false)
                }
                guard let pointer = try? String(contentsOfFile: gitPath, encoding: .utf8),
                      let gitDir = parseGitdirPointer(pointer, relativeTo: dir) else { return nil }
                // Linked worktrees resolve to <repo>/.git/worktrees/<name>.
                // Submodules are also gitdir-pointer checkouts but resolve to
                // .git/modules/… — and a repo merely *located under* a
                // directory named "worktrees" must not match either.
                return headInfo(gitDir: gitDir, isWorktree: gitDir.contains("/.git/worktrees/"))
            }
            let parent = (dir as NSString).deletingLastPathComponent
            if parent == dir || parent.isEmpty { return nil }
            dir = parent
        }
        return nil
    }

    static func headInfo(gitDir: String, isWorktree: Bool) -> GitBranchInfo? {
        guard let head = try? String(contentsOfFile: gitDir + "/HEAD", encoding: .utf8),
              let branch = parseHEAD(head) else { return nil }
        return GitBranchInfo(branch: branch, isWorktree: isWorktree)
    }

    /// "ref: refs/heads/<branch>" → branch name; a detached 40-hex HEAD → its
    /// 7-char short SHA.
    static func parseHEAD(_ content: String) -> String? {
        let line = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else { return nil }
        if line.hasPrefix("ref: ") {
            let ref = String(line.dropFirst("ref: ".count))
            let headsPrefix = "refs/heads/"
            let branch = ref.hasPrefix(headsPrefix) ? String(ref.dropFirst(headsPrefix.count)) : ref
            return branch.isEmpty ? nil : branch
        }
        guard line.count >= 7, line.allSatisfy({ $0.isHexDigit }) else { return nil }
        return String(line.prefix(7))
    }

    /// ".git" pointer file body: "gitdir: <absolute-or-relative path>".
    static func parseGitdirPointer(_ content: String, relativeTo dir: String) -> String? {
        let line = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard line.hasPrefix("gitdir:") else { return nil }
        var path = String(line.dropFirst("gitdir:".count)).trimmingCharacters(in: .whitespaces)
        guard !path.isEmpty else { return nil }
        if !path.hasPrefix("/") {
            path = (dir as NSString).appendingPathComponent(path)
        }
        return (path as NSString).standardizingPath
    }
}
