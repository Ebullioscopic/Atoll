/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
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
import Defaults
import AppKit

class IdleAnimationManager {
    static let shared = IdleAnimationManager()
    
    // Storage directory for user-imported animations
    private let storageDirectory: URL
    
    // MARK: - Lazy Loading Cache
    
    /// Cached animation data with last access timestamp for eviction
    private var loadedAnimations: [String: (data: Data, lastAccess: Date)] = [:]
    
    /// Serial queue serializing all reads and writes to loadedAnimations (fix #8)
    private let animationsQueue = DispatchQueue(label: "com.atoll.idleAnimationManager.animations")

    /// Timer that periodically checks for stale cached animations
    private var evictionTimer: Timer?
    
    /// Returns cached animation data for the given animation, loading from disk on demand.
    /// Evicts entries after 60 seconds of non-use.
    func animationData(for animation: CustomIdleAnimation) -> Data? {
        let key = animation.id.uuidString
        
        // Fix #8: serialize loadedAnimations access via animationsQueue
        if let entry = animationsQueue.sync(execute: { loadedAnimations[key] }) {
            animationsQueue.async { [weak self] in
                self?.loadedAnimations[key] = (data: entry.data, lastAccess: Date())
            }
            return entry.data
        }
        
        // Fix #7: this is a synchronous accessor. Read directly on the caller's
        // thread — the previous `global(...).sync` hop blocked the caller anyway
        // (no async benefit) while a comment falsely claimed it never blocks main.
        // Callers that must not block main should invoke this off the main thread.
        guard let data = loadAnimationDataFromDisk(animation) else { return nil }
        animationsQueue.async { [weak self] in
            self?.loadedAnimations[key] = (data: data, lastAccess: Date())
        }
        startEvictionTimerIfNeeded()
        print("💤 [IdleAnimationManager] Lazy-loaded animation data: \(animation.name)")
        return data
    }
    
    /// Load raw JSON data from disk for a given animation
    private func loadAnimationDataFromDisk(_ animation: CustomIdleAnimation) -> Data? {
        switch animation.source {
        case .lottieFile(let url):
            return try? Data(contentsOf: url)
        case .lottieURL(let url):
            // For remote URLs, attempt synchronous load (caller should prefer async in practice)
            return try? Data(contentsOf: url)
        }
    }
    
    /// Starts the eviction timer if not already running
    private func startEvictionTimerIfNeeded() {
        guard evictionTimer == nil else { return }
        evictionTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            self?.evictStaleAnimations()
        }
    }
    
    /// Evicts cached animation data that hasn't been accessed in 60 seconds
    private func evictStaleAnimations() {
        let threshold: TimeInterval = 60
        let now = Date()
        // Fix #8: serialize loadedAnimations mutation via animationsQueue
        animationsQueue.async { [weak self] in
            guard let self else { return }
            let before = self.loadedAnimations.count
            self.loadedAnimations = self.loadedAnimations.filter {
                now.timeIntervalSince($0.value.lastAccess) < threshold
            }
            let evicted = before - self.loadedAnimations.count
            if evicted > 0 {
                print("🧹 [IdleAnimationManager] Evicted \(evicted) stale animation(s) from cache")
            }
            if self.loadedAnimations.isEmpty {
                DispatchQueue.main.async { [weak self] in
                    self?.evictionTimer?.invalidate()
                    self?.evictionTimer = nil
                }
            }
        }
    }
    
    /// Manually evict all cached data (e.g. on memory pressure)
    func evictAllCachedAnimations() {
        // Fix #8: serialize loadedAnimations mutation via animationsQueue
        animationsQueue.async { [weak self] in
            self?.loadedAnimations.removeAll()
        }
        evictionTimer?.invalidate()
        evictionTimer = nil
        print("🧹 [IdleAnimationManager] Evicted all cached animations (memory pressure)")
    }
    
    private init() {
        // Create storage directory in Application Support
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        storageDirectory = appSupport.appendingPathComponent("DynamicIsland/IdleAnimations", isDirectory: true)
        
        // Create directory if it doesn't exist
        try? FileManager.default.createDirectory(at: storageDirectory, withIntermediateDirectories: true)
        
        print("📁 [IdleAnimationManager] Storage directory: \(storageDirectory.path)")
    }
    
    // MARK: - Initialization
    
    /// Load bundled animations from the LottieAnimations folder
    func initializeDefaultAnimations() {
        var animations: [CustomIdleAnimation] = []
        
        // Load bundled Lottie files
        if let bundledAnimations = loadBundledAnimations() {
            animations.append(contentsOf: bundledAnimations)
        }
        
        // Get existing animations
        var existing = Defaults[.customIdleAnimations]
        
        // Remove any legacy builtInFace entries that may be stored from older versions
        existing.removeAll { animation in
            if case .lottieFile(let url) = animation.source, url.absoluteString == "builtin://face" {
                return true
            }
            return false
        }
        
        if existing.isEmpty {
            // First launch - set everything
            Defaults[.customIdleAnimations] = animations
            Defaults[.selectedIdleAnimation] = animations.first
            print("✅ [IdleAnimationManager] First launch: Initialized with \(animations.count) animations")
        } else {
            // Subsequent launch - ensure all bundled animations are present
            let existingNames = Set(existing.filter { $0.isBuiltIn }.map { $0.name })
            
            // Add any missing bundled animations
            for bundledAnim in animations where bundledAnim.isBuiltIn {
                if !existingNames.contains(bundledAnim.name) {
                    existing.insert(bundledAnim, at: existing.firstIndex(where: { !$0.isBuiltIn }) ?? existing.count)
                    print("➕ [IdleAnimationManager] Added missing bundled animation: \(bundledAnim.name)")
                }
            }
            
            Defaults[.customIdleAnimations] = existing
            
            // If current selection was the old built-in face (no longer valid), select first available
            if let selected = Defaults[.selectedIdleAnimation] {
                let isValid: Bool
                switch selected.source {
                case .lottieFile(let url):
                    isValid = url.absoluteString != "builtin://face"
                case .lottieURL:
                    isValid = true
                }
                if !isValid {
                    Defaults[.selectedIdleAnimation] = existing.first
                    print("🔄 [IdleAnimationManager] Migrated selection from legacy face to: \(existing.first?.name ?? "nil")")
                }
            }
            
            print("✅ [IdleAnimationManager] Subsequent launch: \(existing.count) total animations")
        }
    }
    
    // MARK: - Bundled Animations
    
    /// Load animations from the LottieAnimations folder in the bundle
    private func loadBundledAnimations() -> [CustomIdleAnimation]? {
        print("📦 [IdleAnimationManager] Loading bundled animations...")
        
        // The JSON files are added as individual resources, not in a folder
        let bundledFiles = ["Dog waiting", "Moody Dog", "Orange Cat Peeping", "Reindeer"]
        var animations: [CustomIdleAnimation] = []
        
        for filename in bundledFiles {
            if let url = Bundle.main.url(forResource: filename, withExtension: "json") {
                let animation = CustomIdleAnimation(
                    name: filename,
                    source: .lottieFile(url),
                    speed: 1.0,
                    isBuiltIn: true
                )
                animations.append(animation)
                print("✅ [IdleAnimationManager] Loaded bundled animation: \(filename)")
            } else {
                print("⚠️ [IdleAnimationManager] Could not find bundled animation: \(filename).json")
            }
        }
        
        guard !animations.isEmpty else {
            print("⚠️ [IdleAnimationManager] No bundled animations found")
            return nil
        }
        
        print("📦 [IdleAnimationManager] Loaded \(animations.count) bundled animations")
        return animations
    }
    
    // MARK: - User Animations
    
    /// Load user-imported animations from storage directory
    private func loadStoredUserAnimations() -> [CustomIdleAnimation]? {
        do {
            let files = try FileManager.default.contentsOfDirectory(at: storageDirectory, includingPropertiesForKeys: nil)
            let jsonFiles = files.filter { $0.pathExtension.lowercased() == "json" }
            
            let animations = jsonFiles.map { url -> CustomIdleAnimation in
                let name = url.deletingPathExtension().lastPathComponent
                return CustomIdleAnimation(
                    name: name,
                    source: .lottieFile(url),
                    speed: 1.0,
                    isBuiltIn: false
                )
            }
            
            if !animations.isEmpty {
                print("💾 [IdleAnimationManager] Loaded \(animations.count) stored user animations")
            }
            return animations.isEmpty ? nil : animations
            
        } catch {
            print("❌ [IdleAnimationManager] Error loading stored animations: \(error)")
            return nil
        }
    }
    
    // MARK: - Import & Export
    
    /// Import a Lottie JSON file from URL (either local file or download from remote)
    func importLottieFile(from url: URL, name: String? = nil, speed: CGFloat = 1.0) -> Result<CustomIdleAnimation, Error> {
        let fileName = name ?? url.deletingPathExtension().lastPathComponent
        
        // If it's a remote URL, download it first
        if url.scheme == "http" || url.scheme == "https" {
            return importRemoteAnimation(from: url, name: fileName, speed: speed)
        }
        
        // Local file import
        return importLocalFile(from: url, name: fileName, speed: speed)
    }
    
    /// Import a local Lottie JSON file
    private func importLocalFile(from sourceURL: URL, name: String, speed: CGFloat) -> Result<CustomIdleAnimation, Error> {
        do {
            // Validate it's a JSON file
            guard sourceURL.pathExtension.lowercased() == "json" else {
                return .failure(AnimationImportError.invalidFileType)
            }
            
            // Validate JSON content (basic check)
            let data = try Data(contentsOf: sourceURL)
            guard let _ = try? JSONSerialization.jsonObject(with: data) else {
                return .failure(AnimationImportError.invalidJSON)
            }
            
            // Generate unique filename
            let uniqueFileName = "\(UUID().uuidString).json"
            let destinationURL = storageDirectory.appendingPathComponent(uniqueFileName)
            
            // Copy file to storage
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
            
            // Create animation object (transforms will be stored separately)
            let animation = CustomIdleAnimation(
                name: name,
                source: .lottieFile(destinationURL),
                speed: speed,
                isBuiltIn: false
            )
            
            // Add to defaults
            var animations = Defaults[.customIdleAnimations]
            animations.append(animation)
            Defaults[.customIdleAnimations] = animations
            
            print("✅ [IdleAnimationManager] Imported local file: \(name)")
            return .success(animation)
            
        } catch {
            print("❌ [IdleAnimationManager] Import failed: \(error)")
            return .failure(error)
        }
    }
    
    /// Import animation from remote URL
    private func importRemoteAnimation(from url: URL, name: String, speed: CGFloat) -> Result<CustomIdleAnimation, Error> {
        // For remote URLs, we store the URL directly (no download)
        // The LottieView will handle downloading when needed
        
        let animation = CustomIdleAnimation(
            name: name,
            source: .lottieURL(url),
            speed: speed,
            isBuiltIn: false
        )
        
        // Add to defaults
        var animations = Defaults[.customIdleAnimations]
        animations.append(animation)
        Defaults[.customIdleAnimations] = animations
        
        print("✅ [IdleAnimationManager] Added remote animation: \(name)")
        return .success(animation)
    }
    
    // MARK: - Management
    
    /// Delete an animation (only user-added ones, not built-in)
    func deleteAnimation(_ animation: CustomIdleAnimation) -> Bool {
        guard !animation.isBuiltIn else {
            print("⚠️ [IdleAnimationManager] Cannot delete built-in animation")
            return false
        }
        
        // Remove from defaults
        var animations = Defaults[.customIdleAnimations]
        guard let index = animations.firstIndex(of: animation) else {
            return false
        }
        animations.remove(at: index)
        Defaults[.customIdleAnimations] = animations
        
        // If it's a local file, delete it from storage
        if case .lottieFile(let url) = animation.source {
            // Only delete if it's in our storage directory (not bundled)
            if url.path.contains(storageDirectory.path) {
                try? FileManager.default.removeItem(at: url)
                print("🗑️ [IdleAnimationManager] Deleted file: \(url.lastPathComponent)")
            }
        }
        
        // If deleted animation was selected, select the first one
        if Defaults[.selectedIdleAnimation] == animation {
            Defaults[.selectedIdleAnimation] = animations.first
        }
        
        print("✅ [IdleAnimationManager] Deleted animation: \(animation.name)")
        return true
    }
    
    /// Update animation properties
    func updateAnimation(_ animation: CustomIdleAnimation, name: String? = nil, speed: CGFloat? = nil) {
        var animations = Defaults[.customIdleAnimations]
        guard let index = animations.firstIndex(where: { $0.id == animation.id }) else {
            return
        }
        
        if let name = name {
            animations[index].name = name
        }
        if let speed = speed {
            animations[index].speed = speed
        }
        
        Defaults[.customIdleAnimations] = animations
        
        // Update selected animation if it's the same one
        if Defaults[.selectedIdleAnimation]?.id == animation.id {
            Defaults[.selectedIdleAnimation] = animations[index]
        }
        
        print("✅ [IdleAnimationManager] Updated animation: \(animation.name)")
    }
}

// MARK: - Error Types
enum AnimationImportError: LocalizedError {
    case invalidFileType
    case invalidJSON
    case downloadFailed
    
    var errorDescription: String? {
        switch self {
        case .invalidFileType:
            return "Only .json files are supported"
        case .invalidJSON:
            return "Invalid Lottie JSON format"
        case .downloadFailed:
            return "Failed to download animation"
        }
    }
}
