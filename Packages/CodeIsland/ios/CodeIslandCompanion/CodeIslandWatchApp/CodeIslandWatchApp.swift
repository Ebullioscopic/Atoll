import SwiftUI

@main
struct CodeIslandWatchApp: App {
    @StateObject private var connection = WatchConnection()

    var body: some Scene {
        WindowGroup {
            WatchContentView()
                .environmentObject(connection)
        }
    }
}
