import XCTest
@testable import Atoll

final class WallpaperBackupTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WallpaperBackupTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testRestoreCopiesBackupAndRemovesIt() throws {
        let backup = directory.appendingPathComponent("backup.plist")
        let store = directory.appendingPathComponent("Index.plist")
        try Data("original".utf8).write(to: backup)
        try Data("artwork".utf8).write(to: store)

        XCTAssertTrue(FullScreenArtworkWindowManager.restoreWallpaperStore(from: backup, to: store))
        XCTAssertEqual(try Data(contentsOf: store), Data("original".utf8))
        XCTAssertFalse(FileManager.default.fileExists(atPath: backup.path))
    }

    func testFailedRestoreKeepsBackup() throws {
        let backup = directory.appendingPathComponent("backup.plist")
        let store = directory.appendingPathComponent("missing-dir/Index.plist")
        try Data("original".utf8).write(to: backup)

        XCTAssertFalse(FullScreenArtworkWindowManager.restoreWallpaperStore(from: backup, to: store))
        XCTAssertTrue(FileManager.default.fileExists(atPath: backup.path))
    }

    func testMissingBackupIsNotARestore() {
        let backup = directory.appendingPathComponent("none.plist")
        let store = directory.appendingPathComponent("Index.plist")
        XCTAssertFalse(FullScreenArtworkWindowManager.restoreWallpaperStore(from: backup, to: store))
    }

    func testStoreReferencingAtollWallpaperIsDetected() {
        let assetID = "6D6834A4-2F0F-479A-B053-7D4DC5CB8EB7"
        let artwork = Data("file:///var/folders/x/atoll_artwork_wallpaper_abc.png".utf8)
        let aerial = Data("Choices \(assetID)".utf8)
        let user = Data("file:///System/Library/Desktop%20Pictures/Sonoma.heic".utf8)

        XCTAssertTrue(FullScreenArtworkWindowManager.wallpaperStoreReferencesAtoll(artwork, liveWallpaperAssetID: assetID))
        XCTAssertTrue(FullScreenArtworkWindowManager.wallpaperStoreReferencesAtoll(aerial, liveWallpaperAssetID: assetID))
        XCTAssertFalse(FullScreenArtworkWindowManager.wallpaperStoreReferencesAtoll(user, liveWallpaperAssetID: assetID))
    }
}
