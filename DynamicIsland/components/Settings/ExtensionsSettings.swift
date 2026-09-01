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
import Defaults
import AtollExtensionKit

struct ExtensionsSettingsView: View {
    @ObservedObject private var authManager = ExtensionAuthorizationManager.shared
    @State private var searchText = ""
    @State private var selectedEntry: ExtensionAuthorizationEntry?
    @State private var showingRemoveConfirmation = false
    
    private func highlightID(_ title: String) -> String {
        "extensions-\(title)"
    }
    
    private var filteredEntries: [ExtensionAuthorizationEntry] {
        guard !searchText.isEmpty else { return authManager.entries }
        let query = searchText.lowercased()
        return authManager.entries.filter {
            $0.bundleIdentifier.lowercased().contains(query) ||
            $0.appName.lowercased().contains(query)
        }
    }
    
    var body: some View {
        Form {
            marketplaceSection

            globalTogglesSection
            
            if authManager.isExtensionsFeatureEnabled {
                authorizedAppsSection
            }
        }
        .navigationTitle("Extensions")
        .alert("Remove Extension", isPresented: $showingRemoveConfirmation, presenting: selectedEntry) { entry in
            Button("Cancel", role: .cancel) { }
            Button("Remove", role: .destructive) {
                authManager.removeEntry(bundleIdentifier: entry.bundleIdentifier)
                selectedEntry = nil
            }
        } message: { entry in
            Text("Remove \(entry.appName) from the authorized extensions list? This will dismiss all active live activities, lock screen widgets, and notch experiences from this app.")
        }
    }
    
    /// Where extensions come from.
    ///
    /// The rest of this page manages extensions that are already installed,
    /// which is no use to somebody who has none: nothing here says they exist
    /// as a thing to go and get, or where. First, then, rather than as a
    /// footnote under the permissions.
    private var marketplaceSection: some View {
        Section {
            Link(destination: URL(string: "https://getatoll.app/marketplace")!) {
                HStack(spacing: 10) {
                    Image(systemName: "bag.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(.tint)
                        .frame(width: 22)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Browse the Marketplace")
                        Text("getatoll.app/marketplace")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .settingsHighlight(id: highlightID("Browse the Marketplace"))
        } header: {
            Text("Get Extensions")
        } footer: {
            Text("Apps built with AtollExtensionKit, collected in one place. Opens in your browser.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var globalTogglesSection: some View {
        Section {
            Defaults.Toggle(String(localized:"Enable third-party extensions"), key: .enableThirdPartyExtensions)
                .settingsHighlight(id: highlightID("Enable third-party extensions"))
            
            if Defaults[.enableThirdPartyExtensions] {
                Defaults.Toggle(String(localized:"Allow extension live activities"), key: .enableExtensionLiveActivities)
                    .settingsHighlight(id: highlightID("Allow extension live activities"))
                
                                Defaults.Toggle(String(localized:"Allow extension lock screen widgets"), key: .enableExtensionLockScreenWidgets)
                    .settingsHighlight(id: highlightID("Allow extension lock screen widgets"))

                                                Defaults.Toggle(String(localized:"Allow extension notch experiences"), key: .enableExtensionNotchExperiences)
                    .settingsHighlight(id: highlightID("Allow extension notch experiences"))

                if Defaults[.enableExtensionNotchExperiences] {
                    VStack(alignment: .leading, spacing: 8) {
                        Defaults.Toggle(String(localized:"Show extension tabs"), key: .enableExtensionNotchTabs)
                            .tint(.accentColor)
                        Defaults.Toggle(String(localized:"Allow minimalistic overrides"), key: .enableExtensionNotchMinimalisticOverrides)
                            .tint(.accentColor)
                        Defaults.Toggle(String(localized:"Allow interactive web content"), key: .enableExtensionNotchInteractiveWebViews)
                            .tint(.accentColor)
                    }
                    .padding(.leading, 4)
                }
                
                Defaults.Toggle(String(localized:"Enable extension diagnostics logging"), key: .extensionDiagnosticsLoggingEnabled)
                    .settingsHighlight(id: highlightID("Enable extension diagnostics logging"))
            }
        } header: {
            Text("Global Settings")
        } footer: {
            if Defaults[.enableThirdPartyExtensions] {
                Text("Third-party apps using AtollExtensionKit can display live activities, lock screen widgets, and dedicated notch experiences. Toggle features above or manage individual app permissions below.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Enable extensions to allow third-party apps to display live activities and lock screen widgets in Atoll.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
    
    private var authorizedAppsSection: some View {
        Section {
            if authManager.entries.isEmpty {
                VStack(alignment: .center, spacing: 12) {
                    Image(systemName: "puzzlepiece.extension")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary.opacity(0.5))
                    
                    Text("No extensions yet")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    
                    Text("Apps using AtollExtensionKit will appear here once they request permission")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            } else {
                if authManager.entries.count > 3 {
                    TextField("Search extensions...", text: $searchText)
                        .textFieldStyle(.roundedBorder)
                }
                
                ForEach(filteredEntries) { entry in
                    ExtensionEntryRow(entry: entry, onRemove: {
                        selectedEntry = entry
                        showingRemoveConfirmation = true
                    })
                }
            }
        } header: {
            HStack {
                Text("App Permissions")
                Spacer()
                if !authManager.entries.isEmpty {
                    Text("\(authManager.entries.count) \(authManager.entries.count == 1 ? "app" : "apps")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .settingsHighlight(id: highlightID("App permissions list"))
        } footer: {
            if !authManager.entries.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Permission States:")
                        .font(.caption.weight(.semibold))
                    
                    HStack(spacing: 16) {
                        Label("Authorized", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Label("Pending", systemImage: "clock.fill")
                            .foregroundStyle(.orange)
                        Label("Denied/Revoked", systemImage: "xmark.circle.fill")
                            .foregroundStyle(.red)
                    }
                    .font(.caption2)
                }
                .foregroundStyle(.secondary)
            }
        }
    }
}

@MainActor
private struct ExtensionEntryRow: View {
    @ObservedObject private var authManager = ExtensionAuthorizationManager.shared
    @ObservedObject private var liveActivityManager = ExtensionLiveActivityManager.shared
    @ObservedObject private var widgetManager = ExtensionLockScreenWidgetManager.shared
    @ObservedObject private var notchExperienceManager = ExtensionNotchExperienceManager.shared
    let entry: ExtensionAuthorizationEntry
    let onRemove: () -> Void
    
    @State private var isExpanded = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Main row
            HStack(spacing: 12) {
                // Status indicator
                statusIndicator
                
                // App info
                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.appName)
                        .font(.system(size: 13, weight: .medium))
                    Text(entry.bundleIdentifier)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                // Expand button
                Button {
                    withAnimation(.snappy(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .buttonStyle(.plain)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.snappy(duration: 0.2)) {
                    isExpanded.toggle()
                }
            }
            
            // Expanded details
            if isExpanded {
                expandedDetails
                    .padding(.top, 12)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.vertical, 8)
    }
    
    private var statusIndicator: some View {
        ZStack {
            Circle()
                .fill(statusColor.opacity(0.15))
                .frame(width: 32, height: 32)
            
            Image(systemName: statusIcon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(statusColor)
        }
    }
    
    private var statusColor: Color {
        switch entry.status {
        case .authorized: return .green
        case .pending: return .orange
        case .denied, .revoked: return .red
        }
    }
    
    private var statusIcon: String {
        switch entry.status {
        case .authorized: return "checkmark.circle.fill"
        case .pending: return "clock.fill"
        case .denied, .revoked: return "xmark.circle.fill"
        }
    }
    
    private var expandedDetails: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Status info
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Status:")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(entry.status.rawValue.capitalized)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(statusColor.opacity(0.15))
                        .foregroundStyle(statusColor)
                        .clipShape(Capsule())
                }
                
                if let grantedAt = entry.grantedAt {
                    infoRow(label: "Granted", value: formatDate(grantedAt))
                }
                
                if let lastActivity = entry.lastActivityAt {
                    infoRow(label: "Last Activity", value: formatDate(lastActivity))
                }
                
                if let deniedReason = entry.lastDeniedReason {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Last Denied Reason:")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(deniedReason)
                            .font(.caption)
                            .foregroundStyle(.red.opacity(0.9))
                    }
                }
            }
            
            Divider()
            
            // Scopes section
            if entry.status == .authorized {
                scopeToggles
                Divider()
            }
            
            // Rate limits info
                if let rateLimitRecord = authManager.rateLimitRecords.first(where: { $0.bundleIdentifier == entry.bundleIdentifier }),
                    !rateLimitRecord.activityTimestamps.isEmpty || !rateLimitRecord.widgetTimestamps.isEmpty || !rateLimitRecord.notchExperienceTimestamps.isEmpty {
                rateLimitInfo(record: rateLimitRecord)
                Divider()
            }
            
            // Actions
            actionButtons
        }
        .padding(12)
        .background(Color.secondary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
    
    private var scopeToggles: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Allowed Features")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            
            Toggle("Live Activities", isOn: Binding(
                get: { entry.allowedScopes.contains(.liveActivities) },
                set: { enabled in
                    var newScopes = entry.allowedScopes
                    if enabled {
                        newScopes.insert(.liveActivities)
                    } else {
                        newScopes.remove(.liveActivities)
                    }
                    authManager.updateAllowedScopes(bundleIdentifier: entry.bundleIdentifier, allowedScopes: newScopes)
                }
            ))
            .font(.caption)
            .disabled(!authManager.areLiveActivitiesEnabled)
            
            Toggle("Lock Screen Widgets", isOn: Binding(
                get: { entry.allowedScopes.contains(.lockScreenWidgets) },
                set: { enabled in
                    var newScopes = entry.allowedScopes
                    if enabled {
                        newScopes.insert(.lockScreenWidgets)
                    } else {
                        newScopes.remove(.lockScreenWidgets)
                    }
                    authManager.updateAllowedScopes(bundleIdentifier: entry.bundleIdentifier, allowedScopes: newScopes)
                }
            ))
            .font(.caption)
            .disabled(!authManager.areLockScreenWidgetsEnabled)

            Toggle("Notch Experiences", isOn: Binding(
                get: { entry.allowedScopes.contains(.notchExperiences) },
                set: { enabled in
                    var newScopes = entry.allowedScopes
                    if enabled {
                        newScopes.insert(.notchExperiences)
                    } else {
                        newScopes.remove(.notchExperiences)
                    }
                    authManager.updateAllowedScopes(bundleIdentifier: entry.bundleIdentifier, allowedScopes: newScopes)
                }
            ))
            .font(.caption)
            .disabled(!authManager.areNotchExperiencesEnabled)
        }
    }
    
    private func rateLimitInfo(record: ExtensionRateLimitRecord) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent Activity (last 5 minutes)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            
            HStack(spacing: 20) {
                if !record.activityTimestamps.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Live Activities")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text("\(record.activityTimestamps.count)")
                            .font(.caption.monospacedDigit())
                    }
                }
                
                if !record.widgetTimestamps.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Widget Updates")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text("\(record.widgetTimestamps.count)")
                            .font(.caption.monospacedDigit())
                    }
                }

                if !record.notchExperienceTimestamps.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Notch Experiences")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text("\(record.notchExperienceTimestamps.count)")
                            .font(.caption.monospacedDigit())
                    }
                }
            }
            
            Button("Reset Rate Limits") {
                authManager.resetRateLimits(for: entry.bundleIdentifier)
            }
            .font(.caption)
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }
    
    private var actionButtons: some View {
        HStack(spacing: 8) {
            switch entry.status {
            case .pending:
                Button("Authorize") {
                    authManager.authorize(bundleIdentifier: entry.bundleIdentifier, appName: entry.appName)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                
                Button("Deny") {
                    authManager.deny(bundleIdentifier: entry.bundleIdentifier, reason: "Denied by user")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                
            case .authorized:
                Button("Revoke Access") {
                    authManager.revoke(bundleIdentifier: entry.bundleIdentifier, reason: "Revoked by user")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(.orange)
                
            case .denied, .revoked:
                Button("Re-authorize") {
                    authManager.authorize(bundleIdentifier: entry.bundleIdentifier, appName: entry.appName)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            
            Spacer()
            
            resetMenu

            Button("Remove") {
                onRemove()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(.red)
        }
    }

    private var resetMenu: some View {
        Menu {
            Button("Reset Live Activities") {
                liveActivityManager.dismissAll(for: entry.bundleIdentifier)
            }
            .disabled(!hasLiveActivities)

            Button("Reset Lock Screen Widgets") {
                widgetManager.dismissAll(for: entry.bundleIdentifier)
            }
            .disabled(!hasWidgets)

            Button("Reset Notch Experiences") {
                notchExperienceManager.dismissAll(for: entry.bundleIdentifier)
            }
            .disabled(!hasNotchExperiences)
        } label: {
            Label("Reset", systemImage: "arrow.counterclockwise.circle")
        }
        .menuStyle(.borderlessButton)
        .controlSize(.small)
    }

    private var hasLiveActivities: Bool {
        liveActivityManager.activeActivities.contains { $0.bundleIdentifier == entry.bundleIdentifier }
    }

    private var hasWidgets: Bool {
        widgetManager.activeWidgets.contains { $0.bundleIdentifier == entry.bundleIdentifier }
    }

    private var hasNotchExperiences: Bool {
        notchExperienceManager.activeExperiences.contains { $0.bundleIdentifier == entry.bundleIdentifier }
    }
    
    private func infoRow(label: String, value: String) -> some View {
        HStack {
            Text("\(label):")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption)
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: .now)
    }
}

#Preview {
    ExtensionsSettingsView()
}
