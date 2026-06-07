// FineTune/Utilities/DeviceIconCache.swift
import AppKit

/// LRU cache for device icons to avoid repeated disk I/O on BT device reconnects.
/// Thread-safe: accessed only from @MainActor contexts.
@MainActor
final class DeviceIconCache {
    static let shared = DeviceIconCache()

    private var cache: [String: NSImage] = [:]
    private var order: [String] = []
    private let maxSize: Int

    init(maxSize: Int = 30) {
        self.maxSize = maxSize
    }

    /// Returns cached icon or loads via the provided closure and caches it.
    func icon(for uid: String, loader: () -> NSImage?) -> NSImage? {
        if let cached = cache[uid] {
            moveToFront(uid)
            return cached
        }
        guard let icon = loader() else { return nil }
        insert(uid, icon)
        return icon
    }

    /// Clears the cache (useful for testing or memory pressure).
    func clear() {
        cache.removeAll()
        order.removeAll()
    }

    private func moveToFront(_ uid: String) {
        order.removeAll { $0 == uid }
        order.insert(uid, at: 0)
    }

    private func insert(_ uid: String, _ icon: NSImage) {
        cache[uid] = icon
        order.insert(uid, at: 0)

        // Evict oldest entries if over capacity
        while order.count > maxSize {
            if let removed = order.popLast() {
                cache.removeValue(forKey: removed)
            }
        }
    }
}
