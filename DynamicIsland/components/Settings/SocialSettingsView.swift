/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

import SwiftUI
import Defaults

struct SocialSettingsView: View {
    @ObservedObject private var manager = WhatsAppManager.shared

    @Default(.whatsAppEnabled) var whatsAppEnabled

    @State private var disconnecting = false

    var body: some View {
        Form {
            // MARK: - WhatsApp Card
            Section {
                HStack(spacing: 12) {
                    // App icon style
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(LinearGradient(
                                colors: [Color(red: 0.07, green: 0.73, blue: 0.42),
                                         Color(red: 0.04, green: 0.52, blue: 0.30)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ))
                            .frame(width: 44, height: 44)
                        Image(systemName: "bubble.left.and.bubble.right.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(.white)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text("WhatsApp")
                            .font(.headline)
                        Text("Notifiche native nella Dynamic Island")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Toggle("", isOn: $whatsAppEnabled)
                        .labelsHidden()
                }
                .padding(.vertical, 4)

            } header: {
                Text("Social")
            }

            // MARK: - Status & Controls (only when enabled)
            if whatsAppEnabled {
                Section {
                    // Connection status row
                    HStack(spacing: 10) {
                        ZStack {
                            Circle()
                                .fill(statusColor.opacity(0.15))
                                .frame(width: 28, height: 28)
                            Image(systemName: statusIcon)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(statusColor)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text(statusTitle)
                                .font(.subheadline.weight(.medium))
                            Text(statusSubtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()
                    }
                    .padding(.vertical, 4)

                    // Action buttons
                    HStack(spacing: 10) {
                        if manager.authState != .authenticated {
                            Button {
                                manager.connectWhatsApp()
                            } label: {
                                Label("Connetti WhatsApp", systemImage: "qrcode")
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(Color(red: 0.07, green: 0.73, blue: 0.42))
                        } else {
                            Button(role: .destructive) {
                                disconnecting = true
                                manager.disconnect()
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { disconnecting = false }
                            } label: {
                                if disconnecting {
                                    ProgressView().controlSize(.small)
                                } else {
                                    Label("Disconnetti", systemImage: "person.crop.circle.badge.minus")
                                }
                            }
                            .disabled(disconnecting)
                        }
                    }
                    .padding(.vertical, 2)

                } header: {
                    Text("Stato Connessione")
                } footer: {
                    Text(footerText)
                }

                // MARK: - How it works
                if manager.authState != .authenticated {
                    Section {
                        VStack(alignment: .leading, spacing: 12) {
                            NativeStepRow(number: 1,
                                         icon: "qrcode.viewfinder",
                                         title: "Clicca \"Connetti WhatsApp\"",
                                         subtitle: "Si aprirà una finestra con WhatsApp Web")
                            NativeStepRow(number: 2,
                                         icon: "iphone",
                                         title: "Scansiona il QR dal telefono",
                                         subtitle: "WhatsApp → Dispositivi collegati → Collega un dispositivo")
                            NativeStepRow(number: 3,
                                         icon: "bell.badge.fill",
                                         title: "Ricevi notifiche nella Dynamic Island",
                                         subtitle: "Rispondi direttamente dal notch, senza aprire nessuna app")
                        }
                        .padding(.vertical, 6)
                    } header: {
                        Text("Come funziona")
                    }
                }

                Section {
                    Button {
                        manager.showPreviewNotification()
                    } label: {
                        Label("Anteprima notifica", systemImage: "sparkles.rectangle.stack")
                    }
                    .buttonStyle(.bordered)
                    .tint(Color(red: 0.07, green: 0.73, blue: 0.42))
                } header: {
                    Text("Anteprima")
                } footer: {
                    Text("Mostra una notifica di esempio nella Dynamic Island per testare animazioni, espansione e chiusura. Tocca di nuovo il pulsante per ripetere l'anteprima.")
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Computed

    private var statusTitle: String {
        switch manager.authState {
        case .idle:          return "In attesa"
        case .loading:       return "Caricamento…"
        case .qrRequired:    return "QR richiesto"
        case .authenticated: return "Connesso"
        case .error:         return "Errore"
        }
    }

    private var statusSubtitle: String {
        switch manager.authState {
        case .idle:          return "Abilita l'integrazione per iniziare"
        case .loading:       return "Connessione a WhatsApp Web in corso…"
        case .qrRequired:    return "Clicca \"Connetti WhatsApp\" e scansiona il QR"
        case .authenticated: return "I messaggi arriveranno nella Dynamic Island"
        case .error(let e):  return "Errore: \(e)"
        }
    }

    private var statusIcon: String {
        switch manager.authState {
        case .authenticated: return "checkmark"
        case .error:         return "exclamationmark"
        case .qrRequired:    return "qrcode"
        case .loading:       return "arrow.triangle.2.circlepath"
        case .idle:          return "minus"
        }
    }

    private var statusColor: Color {
        switch manager.authState {
        case .authenticated: return .green
        case .error:         return .red
        case .qrRequired:    return .orange
        default:             return .secondary
        }
    }

    private var footerText: String {
        switch manager.authState {
        case .authenticated:
            return "La sessione è persistente. Non dovrai scansionare il QR ad ogni avvio di Atoll."
        case .qrRequired:
            return "Apri la finestra di connessione e scansiona il QR con WhatsApp sul tuo telefono."
        default:
            return "Atoll usa WhatsApp Web nativamente — nessun tool esterno richiesto."
        }
    }
}

// MARK: - Step Row

private struct NativeStepRow: View {
    let number: Int
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.15))
                    .frame(width: 32, height: 32)
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.accentColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
