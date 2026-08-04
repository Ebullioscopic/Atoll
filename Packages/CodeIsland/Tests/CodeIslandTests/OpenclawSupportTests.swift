import XCTest
@testable import CodeIsland
@testable import CodeIslandCore

/// #235 — OpenClaw (openclaw.ai) integration: source registration and the
/// plugin-pack installer, including the JSON5-config safety rules.
final class OpenclawSupportTests: XCTestCase {
    private var sandbox: URL!
    private var openclawDir: String { sandbox.appendingPathComponent(".openclaw").path }
    private var pluginDir: String { openclawDir + "/codeisland-plugin" }
    private var configPath: String { openclawDir + "/openclaw.json" }

    override func setUpWithError() throws {
        sandbox = FileManager.default.temporaryDirectory
            .appendingPathComponent("openclaw-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: sandbox.appendingPathComponent(".openclaw"),
            withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: sandbox)
    }

    private func install() -> Bool {
        ConfigInstaller.installOpenclawPlugin(
            openclawDir: openclawDir,
            openclawPluginDir: pluginDir,
            openclawConfigPath: configPath,
            fm: .default
        )
    }

    // MARK: Source registration

    func testOpenclawSourceIsSupported() {
        XCTAssertEqual(SessionSnapshot.normalizedSupportedSource("openclaw"), "openclaw")
        XCTAssertEqual(SessionSnapshot.normalizedSupportedSource("clawdbot"), "openclaw")
        XCTAssertEqual(SessionSnapshot.normalizedSupportedSource("open-claw"), "openclaw")
    }

    // MARK: Installer

    func testInstallWritesPluginPackAndRegistersInConfig() throws {
        XCTAssertTrue(install())

        let index = try String(contentsOfFile: pluginDir + "/index.ts")
        XCTAssertTrue(index.contains("CodeIsland OpenClaw plugin"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: pluginDir + "/openclaw.plugin.json"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: pluginDir + "/package.json"))

        let config = try JSONSerialization.jsonObject(
            with: Data(contentsOf: URL(fileURLWithPath: configPath))
        ) as? [String: Any]
        let plugins = try XCTUnwrap(config?["plugins"] as? [String: Any])
        let load = try XCTUnwrap(plugins["load"] as? [String: Any])
        XCTAssertTrue(((load["paths"] as? [String]) ?? []).contains(pluginDir))
        let entries = try XCTUnwrap(plugins["entries"] as? [String: Any])
        XCTAssertEqual((entries["codeisland"] as? [String: Any])?["enabled"] as? Bool, true)

        XCTAssertTrue(ConfigInstaller.isOpenclawPluginInstalled(openclawPluginDir: pluginDir, fm: .default))
    }

    func testInstallPreservesUserConfigAndIsIdempotent() throws {
        let userConfig: [String: Any] = [
            "gateway": ["port": 18789],
            "plugins": [
                "load": ["paths": ["/Users/me/my-other-plugin"]],
                "entries": ["weather": ["enabled": true]],
            ],
        ]
        try JSONSerialization.data(withJSONObject: userConfig)
            .write(to: URL(fileURLWithPath: configPath))

        XCTAssertTrue(install())
        XCTAssertTrue(install())  // reinstall must not duplicate

        let config = try JSONSerialization.jsonObject(
            with: Data(contentsOf: URL(fileURLWithPath: configPath))
        ) as? [String: Any]
        XCTAssertNotNil(config?["gateway"], "unrelated user keys must survive")
        let plugins = try XCTUnwrap(config?["plugins"] as? [String: Any])
        let paths = try XCTUnwrap((plugins["load"] as? [String: Any])?["paths"] as? [String])
        XCTAssertEqual(paths.filter { $0 == pluginDir }.count, 1, "no duplicate path entries")
        XCTAssertTrue(paths.contains("/Users/me/my-other-plugin"), "user plugin path must survive")
        let entries = try XCTUnwrap(plugins["entries"] as? [String: Any])
        XCTAssertNotNil(entries["weather"], "user plugin entry must survive")
    }

    func testUnparseableJSON5ConfigIsNeverTouched() throws {
        let json5 = "{ /* my config */ plugins: { entries: {} }, }"
        try json5.write(toFile: configPath, atomically: true, encoding: .utf8)

        XCTAssertFalse(install(), "install must report failure when the config can't be safely merged")
        XCTAssertEqual(try String(contentsOfFile: configPath), json5, "JSON5 config must be byte-identical")
        // Plugin files may exist (harmless without registration).
    }

    func testUninstallRemovesOnlyOurPluginAndRegistration() throws {
        XCTAssertTrue(install())
        // Add a user path after install
        var config = try JSONSerialization.jsonObject(
            with: Data(contentsOf: URL(fileURLWithPath: configPath))
        ) as! [String: Any]
        var plugins = config["plugins"] as! [String: Any]
        var load = plugins["load"] as! [String: Any]
        var paths = load["paths"] as! [String]
        paths.append("/Users/me/keep-me")
        load["paths"] = paths; plugins["load"] = load; config["plugins"] = plugins
        try JSONSerialization.data(withJSONObject: config).write(to: URL(fileURLWithPath: configPath))

        ConfigInstaller.uninstallOpenclawPlugin(
            openclawPluginDir: pluginDir,
            openclawConfigPath: configPath,
            fm: .default
        )

        XCTAssertFalse(FileManager.default.fileExists(atPath: pluginDir))
        let after = try JSONSerialization.jsonObject(
            with: Data(contentsOf: URL(fileURLWithPath: configPath))
        ) as? [String: Any]
        let afterPlugins = try XCTUnwrap(after?["plugins"] as? [String: Any])
        let afterPaths = (afterPlugins["load"] as? [String: Any])?["paths"] as? [String] ?? []
        XCTAssertFalse(afterPaths.contains(pluginDir))
        XCTAssertTrue(afterPaths.contains("/Users/me/keep-me"))
        XCTAssertNil((afterPlugins["entries"] as? [String: Any])?["codeisland"])
    }

    func testMissingOpenclawDirSkipsInstall() {
        let missing = sandbox.appendingPathComponent("nope").path
        XCTAssertTrue(ConfigInstaller.installOpenclawPlugin(
            openclawDir: missing,
            openclawPluginDir: missing + "/codeisland-plugin",
            openclawConfigPath: missing + "/openclaw.json",
            fm: .default
        ), "machines without OpenClaw report success and do nothing")
        XCTAssertFalse(FileManager.default.fileExists(atPath: missing))
    }
}
