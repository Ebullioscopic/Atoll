import AppKit
import Foundation

/// The complete allowlist of Code Island effects that Atoll may request.
public enum CodeIslandSoundEffect: CaseIterable, Hashable, Sendable {
    case sessionStarted
    case attentionRequired
    case completed
    case failed

    public var resourceName: String {
        switch self {
        case .sessionStarted: return "8bit_start"
        case .attentionRequired: return "8bit_approval"
        case .completed: return "8bit_complete"
        case .failed: return "8bit_error"
        }
    }

    /// Resolves only a statically allowlisted WAV. Provider input never becomes
    /// a resource path, and Atoll remains the caller that decides when to play it.
    public func resourceURL(in suppliedBundle: Bundle? = nil) -> URL? {
        if let suppliedBundle,
           let url = Self.find(resourceName, in: suppliedBundle) {
            return url
        }

        #if SWIFT_PACKAGE
        if let url = Self.find(resourceName, in: Bundle.module) {
            return url
        }
        #endif

        if let url = Self.find(resourceName, in: Bundle(for: CodeIslandUIBundleToken.self)) {
            return url
        }
        return Self.find(resourceName, in: .main)
    }

    private static func find(_ name: String, in bundle: Bundle) -> URL? {
        bundle.url(forResource: name, withExtension: "wav", subdirectory: "Sounds")
            ?? bundle.url(forResource: name, withExtension: "wav")
    }
}

/// Thin playback primitive invoked only by Atoll's presentation host.
@MainActor
public final class CodeIslandSoundPlayer {
    public static let shared = CodeIslandSoundPlayer()

    private var activeSound: NSSound?

    public init() {}

    @discardableResult
    public func play(
        _ effect: CodeIslandSoundEffect,
        volumePercent: Int
    ) -> Bool {
        guard let url = effect.resourceURL(),
              let sound = NSSound(contentsOf: url, byReference: false) else {
            return false
        }
        activeSound?.stop()
        sound.volume = Float(min(max(volumePercent, 0), 100)) / 100
        activeSound = sound
        return sound.play()
    }
}

private final class CodeIslandUIBundleToken: NSObject {}
