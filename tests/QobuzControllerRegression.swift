import Foundation
import Darwin

@main
struct QobuzControllerRegression {
    @MainActor static func main() async throws {
        let accepted = Data(#"{"diff":false,"payload":{"bundleIdentifier":"com.qobuz.desktop","title":"Track","artist":"Artist","playing":true,"elapsedTime":0.75,"timestampEpochMicros":1000000500}}"#.utf8)
        let update = try JSONDecoder().decode(NowPlayingUpdate.self, from: accepted)
        let state = QobuzMediaController.state(from: update)
        precondition(state?.title == "Track" && state?.currentTime == 0.75 && state?.isPlaying == true)
        let foreign = Data(#"{"payload":{"bundleIdentifier":"company.thebrowser.Browser","title":"FOREIGN","playing":true}}"#.utf8)
        let foreignUpdate = try JSONDecoder().decode(NowPlayingUpdate.self, from: foreign)
        precondition(QobuzMediaController.state(from: foreignUpdate) == nil)
        var controller: QobuzMediaController? = QobuzMediaController(engineURL: URL(fileURLWithPath: CommandLine.arguments[1]))
        weak var lifetimeProbe = controller
        for _ in 0..<20 {
            if controller?.isWorking == true { break }
            try await Task.sleep(nanoseconds: 50000000)
        }
        precondition(controller?.isWorking == true)
        precondition(controller?.supportsSeeking == false)
        let pidPath = URL(fileURLWithPath: CommandLine.arguments[1]).deletingPathExtension().appendingPathExtension("pid")
        for _ in 0..<100 {
            if FileManager.default.fileExists(atPath: pidPath.path) { break }
            try await Task.sleep(nanoseconds: 50000000)
        }
        let pid = Int32(try String(contentsOf: pidPath, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines))!
        controller = nil
        try await Task.sleep(nanoseconds: 350000000)
        precondition(lifetimeProbe == nil, "stream retained controller")
        precondition(kill(pid, 0) != 0, "helper survived controller deinit")
        print("PASS: dedicated identity, foreign source rejection, seeking capability, controller deinit and child cleanup")
    }
}
