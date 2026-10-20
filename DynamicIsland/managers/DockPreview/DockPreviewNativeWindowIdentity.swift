/* Atoll — Copyright (C) 2026 Atoll Contributors. GPL-3.0-or-later. */
import ApplicationServices
import CoreGraphics
import Darwin

/// Compatibility boundary used by window switchers (including the Aura reference).
/// AX proxy equality/hash is not WindowServer identity: one window can have several
/// proxies, and their geometry can describe only its content area. Resolve the
/// native ID when the OS exports this function; otherwise use a strict unique
/// metadata match. Never link a private framework or assume the symbol exists.
enum DockPreviewNativeWindowIdentity {
    private typealias Getter = @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError
    private static let getter: Getter? = {
        guard let handle = dlopen(nil, RTLD_LAZY) else { return nil }
        defer { dlclose(handle) }
        guard let symbol = dlsym(handle, "_AXUIElementGetWindow") else { return nil }
        return unsafeBitCast(symbol, to: Getter.self)
    }()
    static var isAvailable: Bool { getter != nil }
    static func windowID(for element: AXUIElement) -> CGWindowID? {
        guard let getter else { return nil }
        var id: CGWindowID = 0
        guard getter(element, &id) == .success, id != 0 else { return nil }
        return id
    }
    private typealias Capture = @convention(c) (CGRect, CFArray, UInt32) -> Unmanaged<CGImage>?
    private static let capture: Capture? = {
        guard let handle = dlopen(nil, RTLD_LAZY) else { return nil }
        defer { dlclose(handle) }
        guard let symbol = dlsym(handle, "CGWindowListCreateImageFromArray") else { return nil }
        return unsafeBitCast(symbol, to: Capture.self)
    }()

    /// Aura-compatible backing-store fallback for full-screen/other-Space
    /// windows rejected by ScreenCaptureKit. This legacy symbol is optional;
    /// capture still requires the user's Screen Recording grant.
    static func snapshot(windowID: CGWindowID, width: Int) -> CGImage? {
        guard CGPreflightScreenCaptureAccess(), let capture else { return nil }
        let pointer = UnsafeMutablePointer<UnsafeRawPointer?>.allocate(capacity: 1)
        pointer[0] = UnsafeRawPointer(bitPattern: UInt(windowID))
        defer { pointer.deallocate() }
        guard let windows = CFArrayCreate(kCFAllocatorDefault, pointer, 1, nil),
              let image = capture(.null, windows, (1 << 0) | (1 << 4))?.takeRetainedValue(), image.width > 1, image.height > 1 else { return nil }
        let scale = min(1, min(CGFloat(max(160, min(640, width))) / CGFloat(image.width), 420 / CGFloat(image.height)))
        let target = CGSize(width: max(1, CGFloat(image.width) * scale), height: max(1, CGFloat(image.height) * scale))
        guard let context = CGContext(data: nil, width: Int(target.width), height: Int(target.height), bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(origin: .zero, size: target))
        return context.makeImage()
    }

}
