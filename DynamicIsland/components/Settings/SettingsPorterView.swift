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

import SwiftUI
import UniformTypeIdentifiers

// MARK: - UTType extension

extension UTType {
    /// Custom uniform type identifier for `.atollsettings` files.
    static let atollSettings = UTType(exportedAs: SettingsPorter.utType)
}

// MARK: - SettingsPorterSection

/// Drop-in `Form` section that provides Export and Import buttons for
/// Atoll's custom settings format.  Intended to be embedded inside
/// `GeneralSettings.body` as its own `Section`.
struct SettingsPorterSection: View {

    // MARK: State

    @State private var isExporting = false
    @State private var isImporting = false
    @State private var exportData: Data? = nil

    @State private var alertTitle = ""
    @State private var alertMessage = ""
    @State private var showAlert = false
    @State private var showImportConfirmation = false
    @State private var pendingImportData: Data? = nil
    @State private var isProcessing = false

    // MARK: Body

    var body: some View {
        Section {
            exportRow
            importRow
        } header: {
            Text("Settings Backup")
        } footer: {
            Text("Export your current settings to a \(Text(".atollsettings").fontWeight(.medium)) file you can share or restore later. API keys and authentication tokens are not included.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        // Export file panel
        .fileExporter(
            isPresented: $isExporting,
            document: exportData.map { AtollSettingsDocument(data: $0) },
            contentType: .atollSettings,
            defaultFilename: defaultExportFilename
        ) { result in
            isProcessing = false
            switch result {
            case .success:
                break
            case .failure(let error):
                showError(title: String(localized: "Export Failed"), error: error)
            }
        }
        // Import file panel
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.atollSettings, .json],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                loadImportFile(url: url)
            case .failure(let error):
                showError(title: String(localized: "Import Failed"), error: error)
            }
        }
        // Import confirmation dialog
        .confirmationDialog(
            String(localized: "Replace Current Settings?"),
            isPresented: $showImportConfirmation,
            titleVisibility: .visible
        ) {
            Button("Import and Replace", role: .destructive) {
                applyImport()
            }
            Button("Cancel", role: .cancel) {
                pendingImportData = nil
            }
        } message: {
            Text("This will overwrite all your current Atoll settings with the values from the imported file. This cannot be undone.")
        }
        // Generic alert for errors / success
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
                isImporting = true
            } label: {
                Label("Import…", systemImage: "square.and.arrow.down")
            }
            .controlSize(.small)
            .disabled(isProcessing)
        }
    }

    // MARK: Actions

    private func beginExport() {
        isProcessing = true
        Task.detached(priority: .userInitiated) {
            do {
                let data = try SettingsPorter.exportData()
                await MainActor.run {
                    self.exportData = data
                    self.isExporting = true
                }
            } catch {
                await MainActor.run {
                    self.isProcessing = false
                    self.showError(title: String(localized: "Export Failed"), error: error)
                }
            }
        }
    }

    private func loadImportFile(url: URL) {
        Task.detached(priority: .userInitiated) {
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            do {
                let data = try Data(contentsOf: url)
                // Validate the data before asking the user
                _ = try JSONDecoder().decode(AtollSettingsSnapshot.self, from: data)
                await MainActor.run {
                    self.pendingImportData = data
                    self.showImportConfirmation = true
                }
            } catch {
                await MainActor.run {
                    self.showError(title: String(localized: "Invalid Settings File"), error: error)
                }
            }
        }
    }

    private func applyImport() {
        guard let data = pendingImportData else { return }
        isProcessing = true
        Task.detached(priority: .userInitiated) {
            do {
                try SettingsPorter.importData(data)
                await MainActor.run {
                    self.isProcessing = false
                    self.pendingImportData = nil
                    self.alertTitle = String(localized: "Settings Imported")
                    self.alertMessage = String(localized: "Your settings have been restored successfully. Some changes may require restarting Atoll to take full effect.")
                    self.showAlert = true
                }
            } catch {
                await MainActor.run {
                    self.isProcessing = false
                    self.showError(title: String(localized: "Import Failed"), error: error)
                }
            }
        }
    }

    // MARK: Helpers

    private var defaultExportFilename: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return "Atoll-Settings-\(formatter.string(from: Date())).\(SettingsPorter.fileExtension)"
    }

    private func showError(title: String, error: Error) {
        alertTitle = title
        alertMessage = error.localizedDescription
        showAlert = true
    }
}

// MARK: - AtollSettingsDocument

/// `FileDocument` wrapper so `fileExporter` can write the JSON data to disk.
struct AtollSettingsDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.atollSettings, .json] }

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let fileData = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = fileData
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
