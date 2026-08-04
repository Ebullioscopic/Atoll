import XCTest
@testable import CodeIsland

final class CodexHomeTests: XCTestCase {
    private var savedValue: String?

    override func setUp() {
        super.setUp()
        savedValue = ProcessInfo.processInfo.environment["CODEX_HOME"]
        unsetenv("CODEX_HOME")
    }

    override func tearDown() {
        if let savedValue {
            setenv("CODEX_HOME", savedValue, 1)
        } else {
            unsetenv("CODEX_HOME")
        }
        super.tearDown()
    }

    func testCodexHomeDefaultsToDotCodexWhenUnset() {
        unsetenv("CODEX_HOME")
        XCTAssertEqual(ConfigInstaller.codexHome(), NSHomeDirectory() + "/.codex")
    }

    func testCodexHomeUsesAbsolutePath() {
        setenv("CODEX_HOME", "/abs/path", 1)
        XCTAssertEqual(ConfigInstaller.codexHome(), "/abs/path")
    }

    func testCodexHomeExpandsTilde() {
        setenv("CODEX_HOME", "~/foo", 1)
        XCTAssertEqual(ConfigInstaller.codexHome(), NSHomeDirectory() + "/foo")
    }

    func testCodexHomeBareTildeBecomesHome() {
        setenv("CODEX_HOME", "~", 1)
        XCTAssertEqual(ConfigInstaller.codexHome(), NSHomeDirectory())
    }

    func testCodexHomeEmptyStringFallsBack() {
        setenv("CODEX_HOME", "", 1)
        XCTAssertEqual(ConfigInstaller.codexHome(), NSHomeDirectory() + "/.codex")
    }

    func testCodexHomeWhitespaceFallsBack() {
        setenv("CODEX_HOME", "   ", 1)
        XCTAssertEqual(ConfigInstaller.codexHome(), NSHomeDirectory() + "/.codex")
    }

    func testDisplayCodexPathUsesEnvNameWhenSet() {
        setenv("CODEX_HOME", "/abs/path", 1)
        XCTAssertEqual(ConfigInstaller.displayCodexPath(filename: "hooks.json"), "$CODEX_HOME/hooks.json")
    }

    func testDisplayCodexPathFallsBackWhenUnset() {
        unsetenv("CODEX_HOME")
        XCTAssertEqual(ConfigInstaller.displayCodexPath(filename: "hooks.json"), "~/.codex/hooks.json")
    }

    func testEnableCodexHooksConfigWritesCurrentFeatureName() throws {
        let codexHome = makeTemporaryCodexHome()
        defer { try? FileManager.default.removeItem(at: codexHome) }

        XCTAssertTrue(ConfigInstaller.enableCodexHooksConfig(fm: .default))

        let contents = try String(contentsOf: codexHome.appendingPathComponent("config.toml"), encoding: .utf8)
        XCTAssertTrue(contents.contains("[features]"))
        XCTAssertTrue(contents.contains("hooks = true"))
        XCTAssertFalse(contents.contains("codex_hooks"))
    }

    func testEnableCodexHooksConfigFlipsCurrentFeatureFalse() throws {
        let codexHome = makeTemporaryCodexHome()
        defer { try? FileManager.default.removeItem(at: codexHome) }
        let config = codexHome.appendingPathComponent("config.toml")
        try FileManager.default.createDirectory(at: codexHome, withIntermediateDirectories: true)
        try "[features]\nhooks = false\n".write(to: config, atomically: true, encoding: .utf8)

        XCTAssertTrue(ConfigInstaller.enableCodexHooksConfig(fm: .default))

        let contents = try String(contentsOf: config, encoding: .utf8)
        XCTAssertTrue(contents.contains("hooks = true"))
        XCTAssertFalse(contents.contains("hooks = false"))
    }

    func testEnableCodexHooksConfigMigratesLegacyFeatureName() throws {
        let codexHome = makeTemporaryCodexHome()
        defer { try? FileManager.default.removeItem(at: codexHome) }
        let config = codexHome.appendingPathComponent("config.toml")
        try FileManager.default.createDirectory(at: codexHome, withIntermediateDirectories: true)
        try "[features]\ncodex_hooks = true\n".write(to: config, atomically: true, encoding: .utf8)

        XCTAssertTrue(ConfigInstaller.enableCodexHooksConfig(fm: .default))

        let contents = try String(contentsOf: config, encoding: .utf8)
        XCTAssertTrue(contents.contains("hooks = true"))
        XCTAssertFalse(contents.contains("codex_hooks"))
    }

    func testEnableCodexHooksConfigRemovesLegacyFeatureNameWhenCurrentFeatureAlreadyEnabled() throws {
        let codexHome = makeTemporaryCodexHome()
        defer { try? FileManager.default.removeItem(at: codexHome) }
        let config = codexHome.appendingPathComponent("config.toml")
        try FileManager.default.createDirectory(at: codexHome, withIntermediateDirectories: true)
        try "[features]\nhooks = true # current\ncodex_hooks = true # legacy\n".write(to: config, atomically: true, encoding: .utf8)

        XCTAssertTrue(ConfigInstaller.enableCodexHooksConfig(fm: .default))

        let contents = try String(contentsOf: config, encoding: .utf8)
        XCTAssertTrue(contents.contains("hooks = true"))
        XCTAssertFalse(contents.contains("codex_hooks"))
    }

    private func makeTemporaryCodexHome() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("codeisland-codex-home-\(UUID().uuidString)", isDirectory: true)
        setenv("CODEX_HOME", url.path, 1)
        return url
    }
}
