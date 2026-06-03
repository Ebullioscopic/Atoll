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

import Cocoa

class ShareServiceFinder: NSObject, NSSharingServicePickerDelegate {

    @MainActor
    private var onServicesCaptured: (([NSSharingService]) -> Void)?

    /// Returns share services asynchronously without blocking the UI
    @MainActor
    func findApplicableServices(for items: [Any], timeout: TimeInterval = 2.0) async -> [NSSharingService] {

        let dummyView = NSView(frame: .zero)
        let picker = NSSharingServicePicker(items: items)
        picker.delegate = self

        return await withCheckedContinuation { continuation in
            var didResume = false

            // Capture services callback
            Task { @MainActor in
                self.onServicesCaptured = { services in
                    guard !didResume else { return }
                    didResume = true
                    continuation.resume(returning: services)
                }
            }

            picker.show(relativeTo: dummyView.bounds, of: dummyView, preferredEdge: .minY)

            // Timeout task
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(timeout))
                guard !didResume else { return }
                didResume = true
                print("Warning: timed out waiting for sharing services")
                continuation.resume(returning: [])
            }
        }
    }

    // MARK: NSSharingServicePickerDelegate

    func sharingServicePicker(_ picker: NSSharingServicePicker,
                              sharingServicesForItems items: [Any],
                              proposedSharingServices proposed: [NSSharingService]) -> [NSSharingService] {
        Task { @MainActor in
            self.onServicesCaptured?(proposed)
        }
        return proposed
    }
}
