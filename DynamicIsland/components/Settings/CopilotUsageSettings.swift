import SwiftUI
import Defaults

struct CopilotUsageSettings: View {
    @Default(.enableCopilotProvider) private var enabled
    @Default(.copilotHost) private var savedHost
    @State private var host = ""
    @State private var token = ""
    @State private var message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Defaults.Toggle(key: .enableCopilotProvider) { Text("GitHub Copilot") }
                .onChange(of: enabled) { _, enabled in
                    if !enabled {
                        // Turning the provider off also forgets the saved token.
                        token = ""
                        do {
                            try CopilotTokenStore.delete(host: savedHost)
                            message = nil
                        } catch { message = error.localizedDescription }
                    }
                    LLMUsageManager.shared.refreshAll(force: true)
                }
            if enabled {
                TextField("GitHub host (github.com or tenant.ghe.com)", text: $host)
                SecureField("GitHub token with Copilot access", text: $token)
                HStack {
                    Button("Save connection") {
                        do {
                            let normalized = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                            let secret = token.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !secret.isEmpty else { throw CopilotQuotaError.notConfigured }
                            try CopilotTokenStore.save(secret, host: normalized)
                            savedHost = normalized
                            token = ""
                            message = String(localized: "Saved in Keychain. Refreshing usage…")
                            LLMUsageManager.shared.refreshAll(force: true)
                        } catch { message = error.localizedDescription }
                    }
                    Button("Disconnect") {
                        do {
                            try CopilotTokenStore.delete(host: savedHost)
                            token = ""
                            enabled = false
                            message = String(localized: "Disconnected.")
                            LLMUsageManager.shared.refreshAll(force: true)
                        } catch { message = error.localizedDescription }
                    }
                }
                Text("Monthly Copilot account quota, shared with the desktop app and IDEs. No project hooks required. Tokens are stored in the macOS Keychain and removed when this provider is turned off. Uses GitHub's undocumented copilot_internal/user endpoint, which may change without notice.")
                    .font(.caption).foregroundStyle(.secondary)
                if let message { Text(message).font(.caption).foregroundStyle(.secondary) }
            }
        }
        .onAppear { host = savedHost }
        .onDisappear { token = "" }
        .onChange(of: host) { _, _ in
            token = ""
            message = nil
        }
    }
}
