import Foundation

extension Bundle {
    /// Custom bundle accessor that finds the SPM resource bundle in Contents/Resources/
    /// when running as a signed .app bundle, falling back to Bundle.module for dev builds.
    static let appModule: Bundle = {
        let bundleName = "CodeIsland_CodeIsland"

        // .app bundle: Contents/Resources/<bundleName>.bundle
        if let resourceURL = Bundle.main.resourceURL,
           let bundle = Bundle(url: resourceURL.appendingPathComponent("\(bundleName).bundle")) {
            return bundle
        }

        // SPM dev build fallback
        return Bundle.module
    }()
}
