import XCTest
@testable import CodeIsland

/// Three-way completion notification style and its migration from the
/// legacy autoExpandOnCompletion boolean (#146).
final class CompletionStyleTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suiteName = "CompletionStyleTests"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testDefaultIsExpand() {
        XCTAssertEqual(AppState.completionStyle(defaults: defaults), .expand)
    }

    func testLegacyDisabledBoolMigratesToOff() {
        defaults.set(false, forKey: SettingsKey.autoExpandOnCompletion)
        XCTAssertEqual(AppState.completionStyle(defaults: defaults), .off)
    }

    func testLegacyEnabledBoolStaysExpand() {
        defaults.set(true, forKey: SettingsKey.autoExpandOnCompletion)
        XCTAssertEqual(AppState.completionStyle(defaults: defaults), .expand)
    }

    func testNewKeyWinsOverLegacyBool() {
        defaults.set(false, forKey: SettingsKey.autoExpandOnCompletion)
        defaults.set("glance", forKey: SettingsKey.completionNotificationStyle)
        XCTAssertEqual(AppState.completionStyle(defaults: defaults), .glance)
    }

    func testUnknownRawValueFallsBackToMigration() {
        defaults.set("bogus", forKey: SettingsKey.completionNotificationStyle)
        XCTAssertEqual(AppState.completionStyle(defaults: defaults), .expand)
    }

    func testCompletionStyleL10nKeysExistInAllLanguages() {
        for (lang, table) in L10n.strings {
            for key in [
                "completion_notification", "completion_style_expand",
                "completion_style_glance", "completion_style_off",
                "completion_notification_desc",
            ] {
                XCTAssertNotNil(table[key], "\(lang) missing \(key)")
            }
        }
    }
}
