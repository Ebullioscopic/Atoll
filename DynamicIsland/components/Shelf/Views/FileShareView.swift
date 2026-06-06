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
import Defaults
import SwiftUI
import UniformTypeIdentifiers

struct FileShareView: View {
    @EnvironmentObject private var vm: DynamicIslandViewModel
    @StateObject private var quickShare = QuickShareService.shared
    @StateObject private var localSend = LocalSendService.shared
    @Default(.quickShareProvider) var quickShareProvider: String
    @State private var showQuickSharePopover = false
    @State private var isSwitchHover = false
    @State private var autoCloseToken = UUID()

    @State private var hostView: NSView?
    @State private var interactionNonce: UUID = .init()
    @State private var isProcessing = false
    @State private var pendingDropProviders: [NSItemProvider]?
    @State private var showLocalSendPicker = false
    
    private var selectedProvider: QuickShareProvider {
        quickShare.availableProviders.first(where: { $0.id == quickShareProvider }) ?? QuickShareProvider(id: "System Share Menu", imageData: nil, supportsRawText: true)
    }

    var body: some View {
        dropArea
            .background(NSViewHost(view: $hostView))
            .onAppear {
                quickShare.ensureDiscovered()
                localSend.startDiscovery()
            }
            .onDrop(of: [.fileURL, .url, .utf8PlainText, .plainText, .data, .image], isTargeted: $vm.dropZoneTargeting) { providers in
                interactionNonce = .init()
                vm.dropEvent = true
                if selectedProvider.id == "LocalSend" {
                    pendingDropProviders = providers
                    showLocalSendPicker = true
                } else {
                    Task { await handleDrop(providers) }
                }
                return true
            }
            .onTapGesture {
                guard quickShare.availableProviders.first(where: { $0.id == quickShareProvider }) != nil else { return }
                // Only open picker on taps when AirDrop or LocalSend is selected
                if quickShareProvider == "AirDrop" || quickShareProvider == "LocalSend" {
                    Task { await handleClick() }
                }
            }
    }

    private var dropArea: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(
                    LinearGradient(colors: [Color.black.opacity(0.35), Color.black.opacity(0.20)], startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(
                            vm.dropZoneTargeting
                                ? Color.accentColor.opacity(0.9)
                                : Color.white.opacity(0.1),
                            style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [10])
                        )
                )
                .shadow(color: Color.black.opacity(0.6), radius: 6, x: 0, y: 2)

            // Content
            VStack(spacing: 5) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(
                            vm.dropZoneTargeting ? 0.11 : 0.09
                        ))
                        .frame(width: 55, height: 55)
                    Image(systemName: "square.and.arrow.up")
                    Group {
                        if let imgData = selectedProvider.imageData, let nsImg = NSImage(data: imgData) {
                            Image(nsImage: nsImg)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 34, height: 34)
                                .clipped()
                        } else {
                            Image(systemName: "square.and.arrow.up")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 34, height: 34)
                        }
                    }
                        .foregroundStyle(
                            vm.dropZoneTargeting ? Color.accentColor : Color.gray
                        )
                        .scaleEffect(
                            vm.dropZoneTargeting ? 1.06 : 1.0
                        )
                        .animation(.spring(response: 0.36, dampingFraction: 0.7), value: vm.dropZoneTargeting)
                }

                Text(selectedProvider.id)
                    .font(.system(.headline, design: .rounded))
                    .foregroundColor(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity)

            }
            .padding(18)
            .frame(maxWidth: .infinity)

            // Switch button pinned to top-right corner
            VStack {
                HStack {
                    Spacer()
                    Button {
                        vm.setAutoCloseSuppression(true, token: autoCloseToken)
                        quickShare.ensureDiscovered()
                        showQuickSharePopover.toggle()
                    } label: {
                        Image(systemName: "switch.2")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 14, height: 14)
                            .padding(8)
                            .background(RoundedRectangle(cornerRadius: 8).fill(isSwitchHover ? Color(.windowBackgroundColor).opacity(0.12) : Color.clear))
                            .foregroundColor(isSwitchHover ? .accentColor : .gray)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .onHover { hovering in
                        isSwitchHover = hovering
                        vm.setAutoCloseSuppression(hovering, token: autoCloseToken)
                    }
                    .popover(isPresented: $showQuickSharePopover, arrowEdge: .bottom) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Quick Share")
                                .font(.headline)

                            Picker("Quick Share Service", selection: $quickShareProvider) {
                                ForEach(quickShare.availableProviders, id: \.id) { provider in
                                    HStack(spacing: 8) {
                                        Group {
                                            if let imgData = provider.imageData, let nsImg = NSImage(data: imgData) {
                                                Image(nsImage: nsImg)
                                                    .resizable()
                                                    .scaledToFit()
                                                    .frame(width: 16, height: 16)
                                                    .clipShape(RoundedRectangle(cornerRadius: 3))
                                            } else {
                                                Image(systemName: "square.and.arrow.up")
                                                    .frame(width: 16, height: 16)
                                            }
                                        }
                                        .foregroundColor(.accentColor)

                                        Text(provider.id)
                                            .lineLimit(1)
                                            .truncationMode(.tail)
                                            .layoutPriority(1)
                                            .fixedSize(horizontal: true, vertical: false)
                                    }
                                    .tag(provider.id)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(minWidth: 260)

                            if let selected = quickShare.availableProviders.first(where: { $0.id == quickShareProvider }) {
                                HStack(alignment: .top, spacing: 8) {
                                    Group {
                                        if let imgData = selected.imageData, let nsImg = NSImage(data: imgData) {
                                            Image(nsImage: nsImg)
                                                .resizable()
                                                .scaledToFit()
                                                .frame(width: 20, height: 20)
                                                .clipShape(RoundedRectangle(cornerRadius: 4))
                                        } else {
                                            Image(systemName: "square.and.arrow.up")
                                                .frame(width: 20, height: 20)
                                        }
                                    }
                                    .foregroundColor(.accentColor)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Currently: \(selected.id)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                            .truncationMode(.tail)
                                            .layoutPriority(1)
                                            .fixedSize(horizontal: true, vertical: false)
                                        Text("Files shared from the shelf will use this service")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                        .padding()
                        .onAppear { vm.setAutoCloseSuppression(true, token: autoCloseToken) }
                        .onDisappear {
                            // Delay clearing suppression slightly so the close click doesn't immediately close the notch
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                vm.setAutoCloseSuppression(false, token: autoCloseToken)
                            }
                        }
                        .onHover { hovering in vm.setAutoCloseSuppression(hovering, token: autoCloseToken) }
                    }
                    .padding(.trailing, 8)
                    .padding(.top, 8)
                }
                Spacer()
            }
            
            // Loading overlay
            if isProcessing || quickShare.isPickerOpen {
                RoundedRectangle(cornerRadius: 12)
                    .fill(.black.opacity(0.3))
                    .overlay(
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.8)
                    )
            }

            if selectedProvider.id == "LocalSend" && localSend.isSending {
                VStack {
                    HStack {
                        Spacer()
                        ZStack {
                            Circle()
                                .stroke(Color.white.opacity(0.16), lineWidth: 3)

                            Circle()
                                .trim(from: 0, to: min(max(localSend.sendProgress, 0), 1))
                                .stroke(
                                    Color.white,
                                    style: StrokeStyle(lineWidth: 3, lineCap: .round)
                                )
                                .rotationEffect(.degrees(-90))
                                .animation(.easeInOut(duration: 0.2), value: localSend.sendProgress)

                            if localSend.sendProgress > 0.99 {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(.white)
                            }
                        }
                        .frame(width: 24, height: 24)
                        .padding(.top, 10)
                        .padding(.trailing, 10)
                    }
                    Spacer()
                }
                .transition(.opacity)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onChange(of: showLocalSendPicker) { _, show in
            if show {
                LocalSendDevicePickerWindowManager.shared.show(
                    onDeviceSelected: { device in
                        localSend.selectedDeviceID = device.id
                        if let providers = pendingDropProviders {
                            // Close the picker first since handleDrop will use quickShare properly
                            showLocalSendPicker = false
                            Task {
                                await handleDrop(providers)
                                pendingDropProviders = nil
                            }
                        }
                    },
                    onDismiss: {
                        showLocalSendPicker = false
                        pendingDropProviders = nil
                    }
                )
            } else {
                LocalSendDevicePickerWindowManager.shared.hide()
            }
        }
    }

    // MARK: - Actions

    private func handleDrop(_ providers: [NSItemProvider]) async {
        isProcessing = true
        defer { isProcessing = false }
        await quickShare.shareDroppedFiles(providers, using: selectedProvider, from: hostView)
    }
    
    private func handleClick() async {
        await quickShare.showFilePicker(for: selectedProvider, from: hostView)
    }
}

// MARK: - Host NSView extractor for anchoring share sheet

private struct NSViewHost: NSViewRepresentable {
    @Binding var view: NSView?
    
    func makeNSView(context: Context) -> NSView {
        let v = NSView(frame: .zero)
        DispatchQueue.main.async { self.view = v }
        return v
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { self.view = nsView }
    }
}
