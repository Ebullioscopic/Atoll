/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * Originally from boring.notch project
 * Modified and adapted for Atoll (DynamicIsland)
 * See NOTICE for details.
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <https://www.gnu.org/licenses/>.
 */

import Foundation
import AppKit
import QuickLookThumbnailing
import UniformTypeIdentifiers

actor ThumbnailService {
    static let shared = ThumbnailService()

    private let cache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 200
        cache.totalCostLimit = 64 * 1024 * 1024 // 64 MB
        return cache
    }()
    // NSCache cannot enumerate its keys, so we track them separately to
    // support path-based invalidation in clearCache(for:).
    private var cacheKeys: Set<String> = []
    private var pendingRequests: [String: Task<NSImage?, Never>] = [:]
    private let thumbnailGenerator = QLThumbnailGenerator.shared

    private init() {}

    func thumbnail(for url: URL, size: CGSize) async -> NSImage? {
        let cacheKey = "\(url.path)_\(size.width)x\(size.height)"

        if let cached = cache.object(forKey: cacheKey as NSString) {
            return cached
        }

        if let pending = pendingRequests[cacheKey] {
            return await pending.value
        }

        let task = Task<NSImage?, Never> {
            let thumbnail = await generateQuickLookThumbnail(for: url, size: size)
            if let thumbnail = thumbnail {
                cache.setObject(thumbnail, forKey: cacheKey as NSString, cost: estimatedCost(of: thumbnail))
                cacheKeys.insert(cacheKey)
                // NSCache evicts silently, so `cacheKeys` would grow unbounded.
                // Reconcile against the cache once it exceeds the count limit,
                // dropping keys whose objects are already gone.
                if cacheKeys.count > 256 {
                    cacheKeys = cacheKeys.filter { cache.object(forKey: $0 as NSString) != nil }
                }
            }
            pendingRequests[cacheKey] = nil
            return thumbnail
        }

        pendingRequests[cacheKey] = task
        return await task.value
    }

    func clearCache() {
        cache.removeAllObjects()
        cacheKeys.removeAll()
    }

    func clearCache(for url: URL) {
        // Keys are "<path>_<w>x<h>"; match on the "<path>_" boundary so that
        // invalidating /tmp/a does not also evict /tmp/ab's thumbnails.
        let prefix = "\(url.path)_"
        let keysToRemove = cacheKeys.filter { $0.hasPrefix(prefix) }
        for key in keysToRemove {
            cache.removeObject(forKey: key as NSString)
            cacheKeys.remove(key)
        }
    }

    /// Rough byte estimate (width * height * 4 bytes/pixel) used as the NSCache cost.
    private func estimatedCost(of image: NSImage) -> Int {
        let size = image.size
        return max(1, Int(size.width * size.height * 4))
    }
    
    // MARK: - Private Methods
    
    private func generateQuickLookThumbnail(for url: URL, size: CGSize) async -> NSImage? {
        let scale = await MainActor.run { NSScreen.main?.backingScaleFactor ?? 2.0 }
        
        return await url.accessSecurityScopedResource { scopedURL in
            NSLog("🔐 ThumbnailService: obtaining security scope for \(scopedURL.path)")
            let request = QLThumbnailGenerator.Request(
                fileAt: scopedURL,
                size: size,
                scale: scale,
                representationTypes: .all
            )
            request.iconMode = true

            return await withCheckedContinuation { (continuation: CheckedContinuation<NSImage?, Never>) in
                thumbnailGenerator.generateBestRepresentation(for: request) { representation, error in
                    if let rep = representation {
                        NSLog("🔍 ThumbnailService: generated thumbnail for \(scopedURL.path)")
                        continuation.resume(returning: rep.nsImage)
                    } else {
                        if let err = error { 
                            NSLog("⚠️ ThumbnailService: thumbnail error for \(scopedURL.path): \(err.localizedDescription)") 
                        }
                        continuation.resume(returning: nil)
                    }
                }
            }
        }
    }
}

// MARK: - Extensions

extension QLThumbnailRepresentation {
    var nsImage: NSImage {
        return NSImage(cgImage: self.cgImage, size: self.cgImage.size)
    }
}

extension CGImage {
    var size: NSSize {
        return NSSize(width: self.width, height: self.height)
    }
}
