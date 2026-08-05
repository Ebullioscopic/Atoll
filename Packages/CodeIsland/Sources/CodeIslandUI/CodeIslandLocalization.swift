import Foundation

/// Resolves all Code Island interface copy without taking over Atoll's
/// application-wide language preference or default localization table.
public enum CodeIslandLocalization {
    public static let tableName = "CodeIsland"

    public static func string(
        _ key: String.LocalizationValue,
        comment: StaticString? = nil
    ) -> String {
        #if SWIFT_PACKAGE
        return String(
            localized: key,
            table: tableName,
            bundle: .module,
            comment: comment
        )
        #else
        return String(
            localized: key,
            table: tableName,
            bundle: .main,
            comment: comment
        )
        #endif
    }
}
