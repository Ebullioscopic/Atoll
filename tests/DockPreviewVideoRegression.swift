/* Atoll — Copyright (C) 2026 Atoll Contributors. GPL-3.0-or-later. */
import AppKit
import ApplicationServices
import AVFoundation
import CoreVideo

/// Creates a local silent movie, verifies QuickTime's full-screen window, and cleans it up.
@main
struct DockPreviewVideoRegression {
    static func value(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
        var result: CFTypeRef?; AXUIElementCopyAttributeValue(element, key as CFString, &result); return result
    }
    static func require(_ condition: Bool, _ text: String) throws {
        if !condition { throw NSError(domain: "DockPreviewVideoRegression", code: 1, userInfo: [NSLocalizedDescriptionKey: text]) }
    }
    @MainActor static func main() async throws {
        setbuf(stdout, nil)
        try require(AXIsProcessTrusted() && CGPreflightScreenCaptureAccess(), "Video fixture requires Accessibility and Screen Recording")
        let previous = NSWorkspace.shared.frontmostApplication
        let existing = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.QuickTimePlayerX").first
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("AtollVideoPreview-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let movie = folder.appendingPathComponent("Dock Preview Test Movie.mov")
        defer { try? FileManager.default.removeItem(at: folder); previous?.activate() }
        let writer = try AVAssetWriter(outputURL: movie, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 320, AVVideoHeightKey: 180])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB, kCVPixelBufferWidthKey as String: 320, kCVPixelBufferHeightKey as String: 180])
        writer.add(input)
        try require(writer.startWriting(), "Movie writer starts")
        writer.startSession(atSourceTime: .zero)
        for frame in 0..<24 {
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(10)) }
            var buffer: CVPixelBuffer?
            CVPixelBufferCreate(kCFAllocatorDefault, 320, 180, kCVPixelFormatType_32ARGB, nil, &buffer)
            guard let buffer else { throw NSError(domain: "Movie buffer", code: 1) }
            CVPixelBufferLockBaseAddress(buffer, [])
            if let bytes = CVPixelBufferGetBaseAddress(buffer) {
                let count = CVPixelBufferGetBytesPerRow(buffer) * CVPixelBufferGetHeight(buffer)
                memset(bytes, Int32(100 + frame * 3), count)
            }
            CVPixelBufferUnlockBaseAddress(buffer, [])
            try require(adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(frame), timescale: 24)), "Movie frame written")
        }
        input.markAsFinished()
        await writer.finishWriting()
        try require(writer.status == .completed, "Movie file completed")
        let configuration = NSWorkspace.OpenConfiguration()
        let player: NSRunningApplication = try await withCheckedThrowingContinuation { continuation in
            NSWorkspace.shared.open([movie], withApplicationAt: URL(fileURLWithPath: "/System/Applications/QuickTime Player.app"), configuration: configuration) { app, error in
                if let app { continuation.resume(returning: app) }
                else { continuation.resume(throwing: error ?? NSError(domain: "Open player", code: 1)) }
            }
        }
        let root = AXUIElementCreateApplication(player.processIdentifier)
        var target: AXUIElement?
        for _ in 0..<30 {
            target = (value(root, kAXWindowsAttribute) as? [AXUIElement] ?? []).first { (value($0, kAXTitleAttribute) as? String ?? "").contains("Dock Preview Test Movie") }
            if target != nil { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        guard let target else { throw NSError(domain: "QuickTime movie window missing", code: 1) }
        defer {
            _ = AXUIElementSetAttributeValue(target, "AXFullScreen" as CFString, kCFBooleanFalse)
            if let close = value(target, kAXCloseButtonAttribute), CFGetTypeID(close) == AXUIElementGetTypeID() { _ = AXUIElementPerformAction(close as! AXUIElement, kAXPressAction as CFString) }
            if existing == nil { player.terminate() }
        }
        try require(AXUIElementSetAttributeValue(target, "AXFullScreen" as CFString, kCFBooleanTrue) == .success, "Video enters full screen")
        try await Task.sleep(for: .milliseconds(1200))
        let service = DockPreviewService()
        for otherSpace in [false, true] {
            if otherSpace { previous?.activate(); try await Task.sleep(for: .milliseconds(700)) }
            let windows = await service.windows(for: player.processIdentifier, includeMinimized: true, limit: 12, allowCapture: true)
            guard let video = windows.first(where: { $0.title.contains("Dock Preview Test Movie") && $0.isFullScreen }), let id = video.captureID else { throw NSError(domain: "Full-screen video title/capture identity missing", code: 1) }
            let image = await service.thumbnail(for: id, width: 400)
            try require(image != nil, "Full-screen video snapshot exists, other Space: \(otherSpace)")
        }
        _ = AXUIElementSetAttributeValue(target, "AXFullScreen" as CFString, kCFBooleanFalse)
        try await Task.sleep(for: .milliseconds(1000))
        print("PASS full-screen video title, capture identity, and snapshots on current/other Spaces")
    }
}
