import Foundation

/// Minimal bilingual localization helper for the iOS/watchOS companion app (#260).
///
/// The companion targets never had any localization infrastructure — every string was
/// a hardcoded Chinese literal. Rather than introducing a full key/dictionary catalog
/// (see the Mac app's `Sources/CodeIsland/L10n.swift` for that heavier 7-language
/// pattern), this keeps translations colocated with their call site and just chooses
/// between the original Chinese and a new English string based on the system
/// language: Chinese systems keep seeing Chinese, every other language now sees
/// natural English instead of hardcoded Chinese.
enum L10n {
    /// True when the user's preferred language is Chinese (any script/region).
    static var isChinese: Bool {
        let preferred = Locale.preferredLanguages.first ?? Locale.current.identifier
        return preferred.lowercased().hasPrefix("zh")
    }

    /// Returns `zh` on a Chinese system, `en` everywhere else.
    static func t(zh: String, en: String) -> String {
        isChinese ? zh : en
    }
}
