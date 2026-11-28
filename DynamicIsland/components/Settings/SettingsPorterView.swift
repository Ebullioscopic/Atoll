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

import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - SettingsPorterSection

/// Drop-in `Form` section that provides Export and Import buttons for
/// Atoll's settings backup (a `.json` file). Embedded in `GeneralSettings`.
struct SettingsPorterSection: View {

    // MARK: State

    @State private var alertTitle = ""
    @State private var alertMessage = ""
    @State private var showAlert = false
    @State private var showImportConfirmation = false
    @State private var showRelaunchPrompt = false
    @State private var pendingSettings: [String: Any]? = nil
    @State private var isProcessing = false

    // MARK: Body

    var body: some View {
        Section {
            exportRow
            importRow
        } header: {
            Text("Settings Backup")
        } footer: {
            Text("Export your settings to a file you can restore later or on another Mac. API keys, sign-ins, clipboard history and notes are not included.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .confirmationDialog(
            String(localized: "Replace Current Settings?"),
            isPresented: $showImportConfirmation,
            titleVisibility: .visible
        ) {
            Button("Import and Replace", role: .destructive) {
                applyImport()
            }
            Button("Cancel", role: .cancel) {
                pendingSettings = nil
            }
        } message: {
            Text("This will overwrite all your current Atoll settings with the values from the imported file. This cannot be undone.")
        }
        .alert(String(localized: "Settings Imported"), isPresented: $showRelaunchPrompt) {
            Button("Relaunch Now") {
                SettingsPorter.relaunch()
            }
            Button("Later", role: .cancel) {}
        } message: {
            Text("Your settings have been restored. Relaunch Atoll so every feature picks up the imported settings.")
        }
        .alert(alertTitle, isPresented: $showAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage)
        }
    }

    // MARK: Row views

    private var exportRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Export Settings")
                Text("Save all settings to a file")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                beginExport()
            } label: {
                Label("Export…", systemImage: "square.and.arrow.up")
            }
            .controlSize(.small)
            .disabled(isProcessing)
        }
    }

    private var importRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Import Settings")
                Text("Restore settings from a file")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                beginImport()
            } label: {
                Label("Import…", systemImage: "square.and.arrow.down")
            }
            .controlSize(.small)
            .disabled(isProcessing)
        }
    }

    // MARK: Actions

    private func beginExport() {
        let data: Data
        do {
            data = try SettingsPorter.exportData()
        } catch {
            showError(title: String(localized: "Export Failed"), error: error)
            return
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = defaultExportFilename
        panel.canCreateDirectories = true
        present(panel) { url in
            isProcessing = true
            Task.detached(priority: .userInitiated) {
                do {
                    try data.write(to: url, options: .atomic)
                    await MainActor.run { isProcessing = false }
                } catch {
                    await MainActor.run {
                        isProcessing = false
                        showError(title: String(localized: "Export Failed"), error: error)
                    }
                }
            }
        }
    }

    private func beginImport() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        present(panel) { url in
            isProcessing = true
            Task.detached(priority: .userInitiated) {
                do {
                    let settings = try SettingsPorter.validate(Data(contentsOf: url))
                    await MainActor.run {
                        isProcessing = false
                        pendingSettings = settings
                        showImportConfirmation = true
                    }
                } catch {
                    await MainActor.run {
                        isProcessing = false
                        showError(title: String(localized: "Invalid Settings File"), error: error)
                    }
                }
            }
        }
    }

    private func applyImport() {
        guard let settings = pendingSettings else { return }
        pendingSettings = nil
        SettingsPorter.apply(settings)
        showRelaunchPrompt = true
    }

    // MARK: Helpers

    /// Shows the panel as a sheet on the Settings window when possible.
    private func present(_ panel: NSSavePanel, completion: @escaping (URL) -> Void) {
        let handler: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let url = panel.url else { return }
            completion(url)
        }
        if let window = NSApp.keyWindow {
            panel.beginSheetModal(for: window, completionHandler: handler)
        } else {
            panel.begin(completionHandler: handler)
        }
    }

    private var defaultExportFilename: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return "Atoll Settings \(formatter.string(from: Date())).json"
    }

    private func showError(title: String, error: Error) {
        alertTitle = title
        alertMessage = error.localizedDescription
        showAlert = true
    }
}
