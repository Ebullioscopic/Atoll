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

import AppKit
import Foundation
import UniformTypeIdentifiers

/// Dynamic representation of a sharing provider discovered at runtime
struct QuickShareProvider: Identifiable, Hashable, Sendable {
    var id: String
    var imageData: Data?
    var supportsRawText: Bool
}

class QuickShareService: ObservableObject {
    static let shared = QuickShareService()
    
    @Published var availableProviders: [QuickShareProvider] = []
    @Published var isPickerOpen = false
    private var cachedServices: [String: NSSharingService] = [:]
    // Hold security-scoped URLs during sharing
    private var sharingAccessingURLs: [URL] = []
    private var lifecycleDelegate: SharingLifecycleDelegate?
    private var hasDiscovered = false
    private var discoveryTask: Task<Void, Never>?
   
    init() {
        // Lazy discovery — don't block app launch.
        // Discovery runs on first access (shelf tab / settings Shelf section).
    }

    /// Ensures providers are discovered exactly once. Safe to call multiple times.
    @MainActor
    func ensureDiscovered() {
        guard !hasDiscovered, discoveryTask == nil else { return }
        discoveryTask = Task {
            await discoverAvailableProviders()
        }
    }
    
    // MARK: - Provider Discovery
    
    @MainActor
    func discoverAvailableProviders() async {
        // Move the heavy NSSharingService enumeration off the main thread
        let result: (providers: [QuickShareProvider], services: [String: NSSharingService]) = await Task.detached(priority: .userInitiated) {
            let testItems: [Any] = [
                URL(string: "https://apple.com")! as NSURL,
                "Test Text" as NSString
            ]

            var nativeServices = NSSharingService.sharingServices(forItems: testItems)

            // Manually inject essential system services that the static list may omit
            let manualServiceNames: [NSSharingService.Name] = [
                .composeEmail,
                .sendViaAirDrop,
                .composeMessage,
                .addToSafariReadingList
            ]
            for name in manualServiceNames {
                if let service = NSSharingService(named: name),
                   !nativeServices.contains(where: { $0.title == service.title }) {
                    nativeServices.append(service)
                }
            }

            var providers: [QuickShareProvider] = []
            var services: [String: NSSharingService] = [:]

            // Process each service inside an autoreleasepool so that
            // the large intermediate TIFF / bitmap buffers are freed
            // immediately instead of accumulating across the loop.
            for svc in nativeServices {
                let (provider, shouldCache) = autoreleasepool { () -> (QuickShareProvider, Bool) in
                    let title = svc.title

                    // Downscale to a small thumbnail and store as compressed PNG
                    // to keep total memory footprint minimal.
                    let imgData: Data? = {
                        let src = svc.image
                        let thumbSize = NSSize(width: 32, height: 32)
                        let thumb = NSImage(size: thumbSize)
                        thumb.lockFocus()
                        src.draw(in: NSRect(origin: .zero, size: thumbSize),
                                 from: NSRect(origin: .zero, size: src.size),
                                 operation: .copy, fraction: 1.0)
                        thumb.unlockFocus()

                        guard let tiff = thumb.tiffRepresentation,
                              let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
                        return bitmap.representation(using: .png, properties: [:])
                    }()

                    let supportsRawText = svc.canPerform(withItems: ["Test Text"])
                    let prov = QuickShareProvider(id: title, imageData: imgData, supportsRawText: supportsRawText)
                    let isNew = !providers.contains(prov)
                    return (prov, isNew)
                }

                if shouldCache {
                    providers.append(provider)
                    services[provider.id] = svc
                }
            }

            // Move AirDrop to the top
            if let idx = providers.firstIndex(where: { $0.id == "AirDrop" }) {
                let ad = providers.remove(at: idx)
                providers.insert(ad, at: 0)
            }

            if !providers.contains(where: { $0.id == "LocalSend" }) {
                providers.insert(QuickShareProvider(id: "LocalSend", imageData: nil, supportsRawText: true), at: min(1, providers.count))
            }

            // System Share Menu fallback
            if !providers.contains(where: { $0.id == "System Share Menu" }) {
                providers.append(QuickShareProvider(id: "System Share Menu", imageData: nil, supportsRawText: true))
            }

            return (providers, services)
        }.value

        var providers = result.providers
        if let idx = providers.firstIndex(where: { $0.id == "LocalSend" }) {
            providers[idx].imageData = localSendIconData()
        }

        self.cachedServices = result.services
        self.availableProviders = providers
        self.hasDiscovered = true
        self.discoveryTask = nil
    }

    private func localSendIconData() -> Data? {
        guard let icon = NSImage(named: NSImage.Name("LocalSend")) else {
            return nil
        }
        let thumbSize = NSSize(width: 32, height: 32)
        let thumb = NSImage(size: thumbSize)
        thumb.lockFocus()
        icon.draw(in: NSRect(origin: .zero, size: thumbSize),
                  from: NSRect(origin: .zero, size: icon.size),
                  operation: .copy,
                  fraction: 1.0)
        thumb.unlockFocus()

        guard let tiff = thumb.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff)
        else { return nil }

        return bitmap.representation(using: .png, properties: [:])
    }
    
    // MARK: - File Picker
    @MainActor
    func showFilePicker(for provider: QuickShareProvider, from view: NSView?) async {
        guard !isPickerOpen else {
            print("⚠️ QuickShareService: File picker already open")
            return
        }

        isPickerOpen = true
        SharingStateManager.shared.beginInteraction()

        // Improve interaction in dev/test builds where app activation can be flaky.
        NSApp.activate(ignoringOtherApps: true)

        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.title = "Select Files for \(provider.id)"
        panel.message = "Choose files to share via \(provider.id)"

        let completion: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            defer {
                self?.isPickerOpen = false
                SharingStateManager.shared.endInteraction()
            }

            if response == .OK && !panel.urls.isEmpty {
                Task {
                    await self?.shareFilesOrText(panel.urls, using: provider, from: view)
                }
            }
        }

        if let window = view?.window {
            panel.beginSheetModal(for: window, completionHandler: completion)
        } else {
            let response = panel.runModal()
            completion(response)
        }
    }
    
    // MARK: - Sharing
    @MainActor
    func shareFilesOrText(_ items: [Any], using provider: QuickShareProvider, from view: NSView?) async {
        let fileURLs = items.compactMap { $0 as? URL }.filter { $0.isFileURL }
        // Stop any previous sharing access
        stopSharingAccessingURLs()
        // Start security-scoped access for all file URLs
        sharingAccessingURLs = fileURLs.filter { $0.startAccessingSecurityScopedResource() }

        if provider.id == "LocalSend" {
            SharingStateManager.shared.beginInteraction()
            defer {
                SharingStateManager.shared.endInteraction()
            }

            do {
                try await LocalSendService.shared.send(items: items)
            } catch {
                NSAlert.popError(error)
            }
            stopSharingAccessingURLs()
            return
        }

        // Setup lifecycle delegate to keep notch open during picker/service
        let delegate = SharingStateManager.shared.makeDelegate { [weak self] in
            self?.lifecycleDelegate = nil
            self?.stopSharingAccessingURLs()
        }
        lifecycleDelegate = delegate

        if let svc = cachedServices[provider.id], svc.canPerform(withItems: items) {
            // For direct service path, explicitly mark service interaction start
            delegate.markServiceBegan()
            svc.delegate = delegate
            svc.perform(withItems: items)
        } else {
            let picker = NSSharingServicePicker(items: items)
            picker.delegate = delegate
            delegate.markPickerBegan()
            if let view {
                picker.show(relativeTo: .zero, of: view, preferredEdge: .minY)
            }
        }
    }

    private func stopSharingAccessingURLs() {
        guard !sharingAccessingURLs.isEmpty else { return }
        NSLog("Stopping sharing access to URLs")
        for url in sharingAccessingURLs {
            url.stopAccessingSecurityScopedResource()
        }
        sharingAccessingURLs.removeAll()
    }
// MARK: - SharingServiceDelegate

private class SharingServiceDelegate: NSObject {}
    
    func shareDroppedFiles(_ providers: [NSItemProvider], using shareProvider: QuickShareProvider, from view: NSView?) async {
        var itemsToShare: [Any] = []
        var foundText: String?

        for provider in providers {
            if let webURL = await provider.extractURL() {
                itemsToShare.append(webURL)
            } else if foundText == nil, let text = await provider.extractText() {
                foundText = text
            } else if let itemFileURL = await provider.extractItem() {
                let resolvedURL = await resolveShelfItemBookmark(for: itemFileURL) ?? itemFileURL
                itemsToShare.append(resolvedURL)
            }
        }

        // If text was found, prioritize sharing it.
        if let text = foundText {
            if shareProvider.supportsRawText {
                await shareFilesOrText([text], using: shareProvider, from: view)
            } else {
                if let tempTextURL = await TemporaryFileStorageService.shared.createTempFile(for: .text(text)) {
                    await shareFilesOrText([tempTextURL], using: shareProvider, from: view)
                    TemporaryFileStorageService.shared.removeTemporaryFileIfNeeded(at: tempTextURL)
                } else {
                    await shareFilesOrText([text], using: shareProvider, from: view)
                }
            }
        } else if !itemsToShare.isEmpty {
            await shareFilesOrText(itemsToShare, using: shareProvider, from: view)
        }
    }

    private func resolveShelfItemBookmark(for fileURL: URL) async -> URL? {
        if let item = await ShelfStateViewModel.shared.findItem(by: fileURL) {
            return await ShelfStateViewModel.shared.resolveAndUpdateBookmarkAsync(for: item)
        }
        print("❌ Failed to resolve bookmark for shelf item")
        return nil
    }
}

// MARK: - App Storage Extension for Provider Selection

extension QuickShareProvider {
    static var defaultProvider: QuickShareProvider {
        let svc = QuickShareService.shared

        if let airdrop = svc.availableProviders.first(where: { $0.id == "AirDrop" }) {
            return airdrop
        }
        return svc.availableProviders.first ?? QuickShareProvider(id: "System Share Menu", imageData: nil, supportsRawText: true)
    }
}
