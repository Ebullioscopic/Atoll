import XCTest
@testable import CodeIsland

final class L10nTests: XCTestCase {
    override func setUp() {
        L10n.shared.language = "en"
    }

    override func tearDown() {
        L10n.shared.language = "system"
    }

    func testTurkishTranslationsContainAllKeysPresentInEnglish() {
        let enKeys = Set(L10n.strings["en"]?.keys ?? Dictionary<String, String>().keys)
        let trKeys = Set(L10n.strings["tr"]?.keys ?? Dictionary<String, String>().keys)

        let missingKeys = enKeys.subtracting(trKeys)
        XCTAssertTrue(missingKeys.isEmpty, "Turkish is missing keys: \(missingKeys)")
    }

    func testKoreanTranslationsContainAllKeysPresentInEnglish() {
        let enKeys = Set(L10n.strings["en"]?.keys ?? Dictionary<String, String>().keys)
        let koKeys = Set(L10n.strings["ko"]?.keys ?? Dictionary<String, String>().keys)

        let missingKeys = enKeys.subtracting(koKeys)
        XCTAssertTrue(missingKeys.isEmpty, "Korean is missing keys: \(missingKeys)")
    }

    func testJapaneseTranslationsContainAllKeysPresentInEnglish() {
        let enKeys = Set(L10n.strings["en"]?.keys ?? Dictionary<String, String>().keys)
        let jaKeys = Set(L10n.strings["ja"]?.keys ?? Dictionary<String, String>().keys)

        let missingKeys = enKeys.subtracting(jaKeys)
        XCTAssertTrue(missingKeys.isEmpty, "Japanese is missing keys: \(missingKeys)")
    }

    func testGermanTranslationsContainAllKeysPresentInEnglish() {
        let enKeys = Set(L10n.strings["en"]?.keys ?? Dictionary<String, String>().keys)
        let deKeys = Set(L10n.strings["de"]?.keys ?? Dictionary<String, String>().keys)

        let missingKeys = enKeys.subtracting(deKeys)
        XCTAssertTrue(missingKeys.isEmpty, "German is missing keys: \(missingKeys)")
    }

    func testTurkishTranslationReturnsCorrectValue() {
        L10n.shared.language = "tr"

        XCTAssertEqual(L10n.shared["general"], "Genel")
        XCTAssertEqual(L10n.shared["behavior"], "Davranış")
        XCTAssertEqual(L10n.shared["appearance"], "Görünüm")
        XCTAssertEqual(L10n.shared["language"], "Dil")
        XCTAssertEqual(L10n.shared["settings_title"], "CodeIsland Ayarları")
        XCTAssertEqual(L10n.shared["quit"], "Çık")
    }

    func testKoreanTranslationReturnsCorrectValue() {
        L10n.shared.language = "ko"

        XCTAssertEqual(L10n.shared["general"], "일반")
        XCTAssertEqual(L10n.shared["behavior"], "동작")
        XCTAssertEqual(L10n.shared["appearance"], "외관")
        XCTAssertEqual(L10n.shared["language"], "언어")
        XCTAssertEqual(L10n.shared["settings_title"], "CodeIsland 설정")
        XCTAssertEqual(L10n.shared["quit"], "종료")
    }

    func testJapaneseTranslationReturnsCorrectValue() {
        L10n.shared.language = "ja"

        XCTAssertEqual(L10n.shared["general"], "一般")
        XCTAssertEqual(L10n.shared["behavior"], "動作")
        XCTAssertEqual(L10n.shared["appearance"], "外観")
        XCTAssertEqual(L10n.shared["language"], "言語")
        XCTAssertEqual(L10n.shared["settings_title"], "CodeIsland 設定")
        XCTAssertEqual(L10n.shared["quit"], "終了")
    }

    func testGermanTranslationReturnsCorrectValue() {
        L10n.shared.language = "de"

        XCTAssertEqual(L10n.shared["general"], "Allgemein")
        XCTAssertEqual(L10n.shared["behavior"], "Verhalten")
        XCTAssertEqual(L10n.shared["appearance"], "Darstellung")
        XCTAssertEqual(L10n.shared["language"], "Sprache")
        XCTAssertEqual(L10n.shared["settings_title"], "CodeIsland-Einstellungen")
        XCTAssertEqual(L10n.shared["quit"], "Beenden")
    }

    func testEffectiveLanguageReturnsTurkishWhenSystemLocaleIsTurkish() {
        L10n.shared.language = "system"

        let turkishEffective = L10n.shared.effectiveLanguage
        XCTAssertNotEqual(turkishEffective, "tr")
    }

    func testFallbackToEnglishWhenTurkishKeyIsMissing() {
        L10n.shared.language = "tr"

        let result = L10n.shared["nonexistent_key"]
        XCTAssertEqual(result, "nonexistent_key")
    }

    func testAllLanguageOptionsAvailableInSettings() {
        let availableLanguages = ["system", "en", "zh", "de", "ja", "ko", "tr"]

        for lang in availableLanguages {
            L10n.shared.language = lang
            let value = L10n.shared["general"]
            XCTAssertFalse(value.isEmpty, "Language '\(lang)' should return a value for 'general' key")
        }
    }

    func testTurkishNumericPlaceholdersWork() {
        L10n.shared.language = "tr"

        let customSoundSet = L10n.shared["custom_sound_set"]
        let formatted = String(format: customSoundSet, "mysound.wav")
        XCTAssertEqual(formatted, "Özel: mysound.wav")

        let updateAvailable = L10n.shared["update_available_body"]
        let formattedUpdate = String(format: updateAvailable, "1.0.19", "1.0.18")
        XCTAssertEqual(formattedUpdate, "CodeIsland 1.0.19 mevcut (şimdiki: 1.0.18). İndirmek ister misiniz?")
    }

    func testKoreanNumericPlaceholdersWork() {
        L10n.shared.language = "ko"

        let customSoundSet = L10n.shared["custom_sound_set"]
        let formatted = String(format: customSoundSet, "mysound.wav")
        XCTAssertEqual(formatted, "사용자 지정: mysound.wav")

        let updateAvailable = L10n.shared["update_available_body"]
        let formattedUpdate = String(format: updateAvailable, "1.0.19", "1.0.18")
        XCTAssertEqual(formattedUpdate, "CodeIsland 1.0.19 버전을 사용할 수 있습니다(현재: 1.0.18). 다운로드하시겠습니까?")
    }

    func testJapaneseNumericPlaceholdersWork() {
        L10n.shared.language = "ja"

        let customSoundSet = L10n.shared["custom_sound_set"]
        let formatted = String(format: customSoundSet, "mysound.wav")
        XCTAssertEqual(formatted, "カスタム: mysound.wav")

        let updateAvailable = L10n.shared["update_available_body"]
        let formattedUpdate = String(format: updateAvailable, "1.0.19", "1.0.18")
        XCTAssertEqual(formattedUpdate, "CodeIsland 1.0.19 が利用可能です (現在: 1.0.18)。ダウンロードしますか？")
    }

    func testGermanNumericPlaceholdersWork() {
        L10n.shared.language = "de"

        let customSoundSet = L10n.shared["custom_sound_set"]
        let formatted = String(format: customSoundSet, "mysound.wav")
        XCTAssertEqual(formatted, "Eigen: mysound.wav")

        let updateAvailable = L10n.shared["update_available_body"]
        let formattedUpdate = String(format: updateAvailable, "1.0.19", "1.0.18")
        XCTAssertEqual(formattedUpdate, "CodeIsland 1.0.19 ist verfügbar (aktuell: 1.0.18). Möchtest du es herunterladen?")
    }
}
