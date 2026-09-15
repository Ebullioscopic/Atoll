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
import Defaults
import SwiftUI
import UniformTypeIdentifiers

struct AirDropView: View {
    @EnvironmentObject var vm: DynamicIslandViewModel
    
    @State var trigger: UUID = .init()
    @State var targeting = false
    @Default(.quickShareProvider) var quickShareProvider
    @StateObject private var quickShareService = QuickShareService.shared
    @State private var showShareSettings = false
    @State private var isSwitchHover = false
    
    var body: some View {
        dropArea
            .onDrop(of: [.data], isTargeted: $vm.dropZoneTargeting) { providers in
                trigger = .init()
                vm.dropEvent = true
                DispatchQueue.global().async { beginDrop(providers) }
                return true
            }
    }
    
    var dropArea: some View {
        Rectangle()
            .fill(.white.opacity(0.1))
            .opacity(0.5)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay {
                ZStack {
                    dropLabel

                    // Switch button in the top-right for quick-share settings
                    VStack {
                        HStack {
                            Spacer()
                            Button {
                                quickShareService.ensureDiscovered()
                                showShareSettings.toggle()
                            } label: {
                                Image(systemName: "switch.2")
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 14, height: 14)
                                    .padding(8)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(isSwitchHover ? Color(.windowBackgroundColor).opacity(0.12) : Color.clear)
                                    )
                                    .foregroundColor(isSwitchHover ? .accentColor : .gray)
                                    .contentShape(Rectangle())
                                    .onHover { over in isSwitchHover = over }
                                    .help("Quick Share settings")
                            }
                            .buttonStyle(.plain)
                            .popover(isPresented: $showShareSettings) {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Quick Share")
                                        .font(.headline)

                                    Picker("Quick Share Service", selection: $quickShareProvider) {
                                        ForEach(quickShareService.availableProviders, id: \.id) { provider in
                                            HStack(spacing: 8) {
                                                Group {
                                                    if let imgData = provider.imageData, let nsImg = NSImage(data: imgData) {
                                                        Image(nsImage: nsImg.fitted(toSide: 16))
                                                            .clipShape(RoundedRectangle(cornerRadius: 3))
                                                    } else {
                                                        Image(systemName: "square.and.arrow.up")
                                                            .frame(width: 16, height: 16)
                                                    }
                                                }
                                                .foregroundColor(.accentColor)

                                                Text(provider.id)
                                                    .lineLimit(1)
                                                    .fixedSize(horizontal: true, vertical: false)
                                            }
                                            .tag(provider.id)
                                        }
                                    }
                                    .pickerStyle(.menu)
                                    .frame(minWidth: 260)

                                    if let selected = quickShareService.availableProviders.first(where: { $0.id == quickShareProvider }) {
                                        HStack(alignment: .top, spacing: 8) {
                                            Group {
                                                if let imgData = selected.imageData, let nsImg = NSImage(data: imgData) {
                                                    Image(nsImage: nsImg.fitted(toSide: 20))
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
                                                    .fixedSize(horizontal: true, vertical: false)
                                                Text("Files dropped here will be shared via this service")
                                                    .font(.caption2)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                    }
                                }
                                .padding()
                            }
                            .padding(.trailing, 8)
                            .padding(.top, 8)
                        }
                        Spacer()
                    }
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .contentShape(Rectangle())
    }
    
    var dropLabel: some View {
        VStack(spacing: 8) {
            Image(systemName: "airplayaudio")
            Text("AirDrop")
        }
        .foregroundStyle(.gray)
        .font(.system(.headline, design: .rounded))
        .contentShape(Rectangle())
        .onTapGesture {
            trigger = .init()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                let picker = NSOpenPanel()
                picker.allowsMultipleSelection = true
                picker.canChooseDirectories = true
                picker.canChooseFiles = true
                picker.begin { response in
                    if response == .OK {
                        let drop = AirDrop(files: picker.urls)
                        drop.begin()
                    }
                }
            }
        }
    }
    
    func beginDrop(_ providers: [NSItemProvider]) {
        assert(!Thread.isMainThread)
        guard let urls = providers.interfaceConvert() else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            let drop = AirDrop(files: urls)
            drop.begin()
        }
    }
}
