import Foundation

/// Resolves the Claude Code configuration directory.
///
/// Claude Code honors `$CLAUDE_CONFIG_DIR` and falls back to `~/.claude`. CodeIsland is a
/// GUI app, so it is usually launched from Finder/login items and does **not** inherit the
/// user's shell environment — reading the env var alone is not enough. The chain below adds
/// a user-settable preference (the only thing that reliably survives a Finder launch) and a
/// probe of the common XDG-style location before defaulting.
///
/// Resolution order:
///   1. `claude_config_dir` user preference (Settings → set explicitly)
///   2. `$CLAUDE_CONFIG_DIR` (present when launched from a shell)
///   3. `~/.claude`, when populated — Claude Code's own default must not be shadowed
///   4. `~/.config/claude-code`, when populated
///   5. `~/.claude`
///
/// Rungs 3–4 test for `projects/` specifically; see `isLiveConfigDir`.
public enum ClaudeConfigPaths {
    /// UserDefaults key backing the Settings field.
    public static let preferenceKey = "claude_config_dir"

    private static let cacheLock = NSLock()
    private static var cachedKey: String?
    private static var cachedValue: String?

    /// Absolute path to the resolved Claude config directory (no trailing slash).
    ///
    /// Called per session per refresh tick, so the filesystem probes in `resolve` are
    /// memoized. The cache is keyed on the *inputs* (preference, environment, home)
    /// rather than being a one-shot latch: reading them is cheap and in-memory, while
    /// the probes are syscalls. That keeps the Settings live-preview correct — typing a
    /// new preference changes the key and re-resolves immediately — while the steady
    /// state costs no stat() at all.
    ///
    /// Only filesystem *layout* changes are missed until the inputs change or the app
    /// restarts, which matches the Settings copy ("Restart CodeIsland after changing").
    public static func configDir() -> String {
        let pref = UserDefaults.standard.string(forKey: preferenceKey)
        let env = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"]
        let home = NSHomeDirectory()
        let key = [pref ?? "", env ?? "", home].joined(separator: "\u{0}")

        cacheLock.lock()
        defer { cacheLock.unlock() }
        if key == cachedKey, let cachedValue { return cachedValue }

        let resolved = resolve(
            preference: pref,
            environment: env,
            homeDir: home,
            directoryExists: defaultDirectoryExists
        )
        cachedKey = key
        cachedValue = resolved
        return resolved
    }

    /// The real filesystem probe used by `configDir`. Exposed so the file-vs-directory
    /// distinction is testable — `resolve` takes it injected, which abstracts it away.
    static func defaultDirectoryExists(_ path: String) -> Bool {
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDir)
        return exists && isDir.boolValue
    }

    /// Canonical NFC form of a path, for comparing two paths for identity.
    ///
    /// `configDir()` returns an NFC-normalized value, so a caller comparing it against a
    /// hand-built literal (`home + "/.claude"`) can get a false mismatch when the home
    /// path contains decomposed Unicode. Note that Swift's `==` on String compares by
    /// canonical equivalence and would mask this — the hazard is real only where paths
    /// are compared as bytes or used to key a filesystem operation.
    public static func canonical(_ path: String) -> String {
        path.precomposedStringWithCanonicalMapping
    }

    /// Drop the memoized resolution. Call after creating or moving a config directory
    /// within the app's lifetime; not needed for preference edits, which re-key the cache.
    public static func invalidateCache() {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        cachedKey = nil
        cachedValue = nil
    }

    /// Where per-project transcripts live.
    public static func projectsDir() -> String { configDir() + "/projects" }

    /// The `settings.json` that holds hook configuration.
    public static func settingsPath() -> String { configDir() + "/settings.json" }

    /// Pure resolution core — all inputs injected so the fallback chain is testable
    /// without touching UserDefaults, the environment, or the real filesystem.
    public static func resolve(
        preference: String?,
        environment: String?,
        homeDir: String,
        directoryExists: (String) -> Bool
    ) -> String {
        if let pref = normalized(preference, homeDir: homeDir) { return pref }
        if let env = normalized(environment, homeDir: homeDir) { return env }

        // Claude Code itself has no XDG rung — it reads $CLAUDE_CONFIG_DIR, else ~/.claude.
        // So a live ~/.claude must win over the XDG probe, or a stale ~/.config/claude-code
        // would silently repoint us away from the directory Claude Code actually reads.
        let dotClaude = homeDir + "/.claude"
        if isLiveConfigDir(dotClaude, directoryExists: directoryExists) { return dotClaude }

        let xdg = homeDir + "/.config/claude-code"
        if isLiveConfigDir(xdg, directoryExists: directoryExists) { return xdg }

        return dotClaude
    }

    /// User-visible form — collapses the home prefix back to `~` so Settings and
    /// diagnostics show `~/.config/claude-code/settings.json` rather than a full path.
    public static func displayPath(_ absolute: String, homeDir: String = NSHomeDirectory()) -> String {
        guard absolute == homeDir || absolute.hasPrefix(homeDir + "/") else { return absolute }
        return "~" + absolute.dropFirst(homeDir.count)
    }

    /// A directory only counts as a live Claude config dir if it holds `projects/`.
    ///
    /// `projects/` is written only by Claude Code itself, which makes it the sole reliable
    /// proof. `settings.json` deliberately does NOT count: CodeIsland's own hook installer
    /// creates that file, so treating it as evidence would let us manufacture the very
    /// signal we then read back — an empty `~/.claude` containing nothing but a
    /// CodeIsland-written `settings.json` would outrank the user's real config dir forever.
    /// Note this asks whether `projects` is a DIRECTORY, not merely that the path
    /// exists — a stray regular file of that name must not mark a config dir live.
    static func isLiveConfigDir(_ path: String, directoryExists: (String) -> Bool) -> Bool {
        directoryExists(path + "/projects")
    }

    /// Trims, expands `~`, and drops any trailing slash. Returns nil for empty input.
    ///
    /// `$CLAUDE_CONFIG_DIR` holds a single path — Claude Code reads it verbatim and does
    /// not treat it as a `PATH`-style list, so no separator splitting happens here. That
    /// matters on APFS, where `:` is legal in a filename.
    ///
    /// Claude Code normalizes the path to Unicode NFC before use; we match that so a
    /// decomposed path (as some macOS APIs hand back) still resolves to the same directory.
    static func normalized(_ raw: String?, homeDir: String) -> String? {
        var value = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        if value == "~" { return homeDir.precomposedStringWithCanonicalMapping }
        if value.hasPrefix("~/") { value = homeDir + "/" + value.dropFirst(2) }
        while value.count > 1 && value.hasSuffix("/") { value.removeLast() }

        // Reject anything that cannot be a config dir. A relative path would resolve
        // against the app's cwd, and `/` would yield "//projects" — in both cases the
        // hook installer would happily `createDirectory` at the bogus location and then
        // report success while Claude Code read somewhere else entirely. Falling through
        // to auto-detect is strictly better than acting on a typo.
        guard value.hasPrefix("/"), value != "/" else { return nil }

        return value.precomposedStringWithCanonicalMapping
    }
}
