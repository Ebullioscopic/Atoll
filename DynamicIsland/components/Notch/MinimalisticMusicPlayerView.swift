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

#if canImport(AppKit)
import AppKit
#endif

// Lyrics are shown/hidden only via Defaults[.enableLyrics] in settings. Inline display is used in the player views.

struct MinimalisticMusicPlayerView: View {
    @EnvironmentObject var vm: DynamicIslandViewModel
    let albumArtNamespace: Namespace.ID
    @Default(.showShuffleAndRepeat) private var showCustomControls
    @Default(.musicControlSlots) private var slotConfig
    @Default(.showMediaOutputControl) private var showMediaOutputControl
    @Default(.musicSkipBehavior) private var musicSkipBehavior
    @Default(.showMinimalisticBatteryIndicator) private var showMinimalisticBatteryIndicator
    @ObservedObject private var reminderManager = ReminderLiveActivityManager.shared
    @ObservedObject private var timerManager = TimerManager.shared
    @ObservedObject private var coordinator = DynamicIslandViewCoordinator.shared
    @State private var hudValue: Double = 0
    @State private var hudDragging: Bool = false
    @State private var hudLastDragged: Date = .distantPast
    @Default(.enableReminderLiveActivity) private var enableReminderLiveActivity
    @Default(.enableLyrics) private var enableLyrics
    @Default(.timerPresets) private var timerPresets
    private let seekInterval: TimeInterval = 10
    private let skipMagnitude: CGFloat = 8

    var body: some View {
        if !musicManager.hasActiveSession {
            // Nothing playing state
            VStack(spacing: 0) {
                Spacer(minLength: 0)

                VStack(spacing: 8) {
                    Image(systemName: "music.note.slash")
                        .font(.system(size: 24, weight: .light))
                        .foregroundColor(.gray)
                    Text("Nothing Playing")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.gray)
                }

                Spacer(minLength: 0)

                timerCountdownSection

                reminderList
            }
            .padding(.horizontal, shouldUseDynamicIslandMode(for: vm.screen) ? -4 : 12)
            .padding(.vertical, shouldUseDynamicIslandMode(for: vm.screen) ? 14 : 0)
            .frame(maxWidth: .infinity)
            .frame(height: calculateDynamicHeight())
            .animation(.smooth(duration: 0.3), value: dynamicHeightSignature)
        } else {
            VStack(spacing: 0) {
                if showMinimalisticBatteryIndicator || shouldUseDynamicIslandMode(for: vm.screen) {
                    // ── Battery ON / DI mode: original flat layout (unchanged) ──
                    GeometryReader { headerGeo in
                        let albumArtWidth: CGFloat = 50
                        let spacing: CGFloat = 10
                        // The right-side time label in the progress bar below is 42pt wide,
                        // trailing-aligned, so its center sits 21pt from the right edge.
                        // We use the same 42pt block for the visualizer so the candles
                        // are perfectly centred above the "-00:00" text.
                        let vizBlockWidth: CGFloat = useMusicVisualizer ? 42 : 0
                        let visualizerBarWidth: CGFloat = useMusicVisualizer ? 24 : 0
                        // Leave an extra 8pt gap between the title text and the visualizer.
                        let textWidth = max(0, headerGeo.size.width - albumArtWidth - spacing - (useMusicVisualizer ? (vizBlockWidth + spacing) : 0))
                        HStack(alignment: .center, spacing: spacing) {
                            MinimalisticAlbumArtView(vm: vm, albumArtNamespace: albumArtNamespace)
                                .frame(width: albumArtWidth, height: albumArtWidth)

                            VStack(alignment: .leading, spacing: 1) {
                                if !musicManager.songTitle.isEmpty {
                                    MusicTitleMarqueeView(
                                        text: musicManager.songTitle,
                                        isExplicit: musicManager.isCurrentTrackExplicit,
                                        font: .system(size: 12, weight: .semibold),
                                        nsFont: .subheadline,
                                        textColor: .white,
                                        frameWidth: textWidth,
                                        badgeHeight: 13
                                    )
                                }

                                Text(musicManager.artistName)
                                    .font(.system(size: 10, weight: .regular))
                                    .foregroundColor(Defaults[.playerColorTinting] ? Color(nsColor: musicManager.avgColor).ensureMinimumBrightness(factor: 0.6) : .gray)
                                    .lineLimit(1)

                            }
                            .frame(width: textWidth, alignment: .leading)

                            if useMusicVisualizer {
                                // 48-pt block matches the trailing time-label width so the
                                // candle centre lines up with the centre of "-00:00".
                                ZStack {
                                    visualizer
                                        .frame(width: visualizerBarWidth)
                                }
                                .frame(width: vizBlockWidth)
                            }
                        }
                    }
                    .frame(height: 50)
                } else {
                    // ── Battery OFF (notch mode): U-shaped notch-hugging layout ──
                    notchHuggingHeader
                }

                // Compact progress bar
                progressBar
                    .padding(.top, batteryOffNotchMode ? 4 : 6)
                
                // Compact playback controls
                if shouldShowControlHUDRow {
                    controlHUDRow
                        .padding(.top, 4)
                } else {
                    playbackControls
                        .padding(.top, 4)
                }

                if enableLyrics {
                    lyricsView
                        .padding(.top, 10)
                }

                timerCountdownSection

                reminderList
            }
            .padding(.horizontal, shouldUseDynamicIslandMode(for: vm.screen) ? -4 : 12)
            .padding(.top, shouldUseDynamicIslandMode(for: vm.screen) ? 14 : (batteryOffNotchMode ? 10 : 6))
            .padding(.bottom, shouldUseDynamicIslandMode(for: vm.screen) ? 14 : (batteryOffNotchMode ? 10 : ReminderLiveActivityManager.baselineMinimalisticBottomPadding))
            .frame(maxWidth: .infinity)
            .frame(height: calculateDynamicHeight(), alignment: .top)
            .animation(.smooth(duration: 0.3), value: dynamicHeightSignature)
        }
    }

    // MARK: - TypingLyricView

    struct TypingLyricView: View {
        let text: String
        let color: Color
        let id: Int
        let playbackRate: Double
        let isPlaying: Bool
        @State private var displayed: String = ""
        @State private var lastText: String = ""
        @State private var animationTask: Task<Void, Never>?

        var body: some View {
            Text(displayed)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(color)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)
                .padding(.top, 4)
                .id(id)
                .onChange(of: text) { _, newText in
                    animateTyping(newText)
                }
                .onChange(of: isPlaying) { _, playing in
                    if !playing {
                        animationTask?.cancel()
                    } else if displayed != text {
                        animateTyping(text)
                    }
                }
                .onAppear {
                    animateTyping(text)
                }
                .onDisappear {
                    animationTask?.cancel()
                }
        }

        private func animateTyping(_ newText: String) {
            animationTask?.cancel()
            displayed = ""
            lastText = newText
            let chars = Array(newText)

            animationTask = Task {
                for (i, c) in chars.enumerated() {
                    if Task.isCancelled { return }
                    try? await Task.sleep(for: .milliseconds(Int(30 / max(playbackRate, 0.1))))
                    if Task.isCancelled { return }
                    if lastText == newText {
                        displayed += String(c)
                    }
                }
            }
        }
    }

    private var reminderEntries: [ReminderLiveActivityManager.ReminderEntry] {
        reminderManager.activeWindowReminders
    }

    private var shouldShowReminderList: Bool {
        enableReminderLiveActivity && !reminderEntries.isEmpty
    }

    private var reminderListHeight: CGFloat {
        ReminderLiveActivityManager.additionalHeight(forRowCount: reminderEntries.count)
    }

    private var shouldShowTimerCountdown: Bool {
        coordinator.timerLiveActivityEnabled && timerManager.isExternalTimerActive
    }

    private var brandAccentColor: Color {
        musicManager.brandAccentColor
    }

    private var timerCountdownColor: Color {
        let baseColor: Color
        if let presetId = timerManager.activePresetId,
           let preset = timerPresets.first(where: { $0.id == presetId }) {
            baseColor = preset.color
        } else {
            baseColor = timerManager.timerColor
        }
        return baseColor.ensureMinimumBrightness(factor: 0.75)
    }

    private var timerCountdownText: String {
        timerManager.formattedRemainingTime()
    }

    private var timerDisplayName: String {
        let trimmed = timerManager.timerName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Timer" : trimmed
    }

    private var dynamicHeightSignature: Int {
        var signature = reminderEntries.count * 10
        if enableLyrics { signature += 1 }
        if shouldShowTimerCountdown { signature += 100 }
        if showMinimalisticBatteryIndicator { signature += 1000 }
        return signature
    }

    /// True when the battery indicator is hidden and we are in notch mode (not DI).
    private var batteryOffNotchMode: Bool {
        !showMinimalisticBatteryIndicator && !shouldUseDynamicIslandMode(for: vm.screen)
    }

    private func calculateDynamicHeight() -> CGFloat {
        let isDynamicIsland = shouldUseDynamicIslandMode(for: vm.screen)

        if !batteryOffNotchMode {
            // ── Battery ON / DI: use the exact original height formula ──
            var height: CGFloat = 50 // header
            height += 6 + 4          // progress bar top padding + bar
            height += 54 + 2         // controls + top padding

            if enableLyrics {
                height += 10 + 34 // lyrics padding + estimated height
            }
            if shouldShowTimerCountdown {
                height += minimalisticTimerCountdownBlockHeight
            }
            if shouldShowReminderList {
                height += reminderListHeight
            }

            height += isDynamicIsland ? 14 : 15 // top padding
            height += isDynamicIsland ? 14 : ReminderLiveActivityManager.baselineMinimalisticBottomPadding
            return height
        }

        // ── Battery OFF (notch mode): tighter height for U-shaped layout ──
        // The album art is pulled UP into the notch header area, so the
        // visible header in-flow is only the title + artist text (~26pt).
        var height: CGFloat = 26 // reduced header (text only; art overlaps upward)
        height += 4 + 4          // progress bar top padding + bar
        height += 54 + 2         // controls + top padding

        if enableLyrics {
            height += 10 + 34
        }
        if shouldShowTimerCountdown {
            height += minimalisticTimerCountdownBlockHeight
        }
        if shouldShowReminderList {
            height += reminderListHeight
        }

        height += 10 // top padding
        height += 10 // bottom padding
        return height
    }

    // MARK: - U-Shaped Notch-Hugging Header

    /// Layout that wraps content around the physical notch cutout.
    /// Album art sits to the left of the notch, the visualizer to the right,
    /// and the song title + artist are centered below the notch — producing a
    /// "U" shape.
    private var notchHuggingHeader: some View {
        GeometryReader { geo in
            let totalWidth = geo.size.width
            let albumArtSize: CGFloat = 50
            let visualizerWidth: CGFloat = useMusicVisualizer ? 24 : 0
            // How far to pull the album art and waveform up alongside the notch.
            let notchHeight = vm.effectiveClosedNotchHeight
            let pullUp = max(notchHeight - 4, 20)
            
            ZStack(alignment: .top) {
                // ── Left: Album art ──
                HStack {
                    MinimalisticAlbumArtView(vm: vm, albumArtNamespace: albumArtNamespace)
                        .frame(width: albumArtSize, height: albumArtSize)
                    Spacer()
                }
                .offset(y: -pullUp)
                .frame(width: totalWidth)

                // ── Right: Waveform ──
                if useMusicVisualizer {
                    HStack {
                        Spacer()
                        visualizer
                            .frame(width: visualizerWidth)
                        Spacer()
                            .frame(width: 12)
                    }
                    .offset(y: -pullUp + (albumArtSize - 16) / 2)
                    .frame(width: totalWidth)
                }

                // ── Center: Title + Artist (below the notch) ──
                VStack(alignment: .leading, spacing: 1) {
                    if !musicManager.songTitle.isEmpty {
                        // In the U-shaped layout the visualizer sits in a 48-pt wide zone
                        // (matching the time text) and has a 12-pt right spacer inside it.
                        let textAreaWidth = max(0, totalWidth - albumArtSize - 10 - (useMusicVisualizer ? (visualizerWidth + 12 + 10) : 0))
                        MusicTitleMarqueeView(
                            text: musicManager.songTitle,
                            isExplicit: musicManager.isCurrentTrackExplicit,
                            font: .system(size: 12, weight: .semibold),
                            nsFont: .subheadline,
                            textColor: .white,
                            frameWidth: textAreaWidth,
                            badgeHeight: 13
                        )
                    }

                    Text(musicManager.artistName)
                        .font(.system(size: 10, weight: .regular))
                        .foregroundColor(Defaults[.playerColorTinting] ? Color(nsColor: musicManager.avgColor).ensureMinimumBrightness(factor: 0.6) : .gray)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, albumArtSize + 10)
                // Position so the bottom of the artist text aligns with the
                // bottom of the album art (which was pulled up by pullUp).
                .offset(y: albumArtSize - pullUp - 28)
            }
        }
        .frame(height: 26) // Only the text portion is in-flow; album art overlaps upward
    }

    private var timerCountdownSection: some View {
        VStack(spacing: 0) {
            if shouldShowTimerCountdown {
                timerCountdownView
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.top, shouldShowTimerCountdown ? minimalisticTimerCountdownTopPadding : 0)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: shouldShowTimerCountdown ? minimalisticTimerCountdownBlockHeight : 0, alignment: .top)
        .animation(.smooth(duration: 0.25), value: shouldShowTimerCountdown)
    }

    private func displayFont(size: CGFloat) -> Font {
        .custom("SF Pro Display", size: size)
    }

    private var timerCountdownView: some View {
        GeometryReader { geometry in
            let availableWidth = geometry.size.width
            let preferredCountdownWidth = max(availableWidth * 0.42, 150)
            let maxCountdownWidth = max(availableWidth - 60, 0)
            let countdownWidth = min(preferredCountdownWidth, maxCountdownWidth)
            let marqueeWidth = max(availableWidth - countdownWidth - 12, 0)

            HStack(alignment: .lastTextBaseline, spacing: 12) {
                MarqueeText(
                    .init(get: { timerDisplayName }, set: { _ in }),
                    font: .system(size: 16, weight: .semibold),
                    nsFont: .title3,
                    textColor: timerCountdownColor.opacity(0.85),
                    frameWidth: max(marqueeWidth, 1)
                )
                .alignmentGuide(.lastTextBaseline) { dimensions in
                    dimensions[VerticalAlignment.bottom]
                }

                Spacer(minLength: 8)

                Text(timerCountdownText)
                    .font(displayFont(size: 56))
                    .monospacedDigit()
                    .foregroundStyle(timerManager.isOvertime ? Color.red : timerCountdownColor)
                    .contentTransition(.numericText())
                    .animation(.smooth(duration: 0.25), value: timerManager.remainingTime)
                    .lineLimit(1)
                    .frame(width: countdownWidth, alignment: .trailing)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 4)
        .frame(height: minimalisticTimerCountdownContentHeight, alignment: .top)
    }

    private var reminderList: some View {
        MinimalisticReminderEventListView(reminders: reminderEntries)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: reminderListHeight, alignment: .top)
            .opacity(shouldShowReminderList ? 1 : 0)
            .animation(.easeInOut(duration: 0.18), value: shouldShowReminderList)
            .environmentObject(vm)
    }

    private var lyricsView: some View {
        let line = musicManager.currentLyrics.trimmingCharacters(in: .whitespacesAndNewlines)
        let transition: AnyTransition = .asymmetric(
            insertion: .move(edge: .bottom).combined(with: .opacity),
            removal: .move(edge: .top).combined(with: .opacity)
        )

        return HStack(spacing: 6) {
            if !line.isEmpty {
                Image(systemName: "music.note")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.7))
                    .symbolRenderingMode(.monochrome)

                Text(line)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.88))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.trailing, 6)
                    .id(line)
                    .transition(transition)
            }
        }
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.smooth(duration: 0.32), value: line)
    }
    

private struct MinimalisticReminderEventListView: View {
    let reminders: [ReminderLiveActivityManager.ReminderEntry]

    private let textFont = Font.system(size: 13, weight: .regular)
    private let separatorSpacing: CGFloat = 10

    var body: some View {
        VStack(alignment: .leading, spacing: ReminderLiveActivityManager.listRowSpacing) {
            ForEach(reminders) { entry in
                MinimalisticReminderEventRow(entry: entry, textFont: textFont, separatorSpacing: separatorSpacing)
            }
        }
        .padding(.top, ReminderLiveActivityManager.listTopPadding)
    }
}

private struct MinimalisticReminderEventRow: View {
    let entry: ReminderLiveActivityManager.ReminderEntry
    let textFont: Font
    let separatorSpacing: CGFloat

    @EnvironmentObject private var vm: DynamicIslandViewModel
    @State private var didCopyLink = false
    @State private var copyResetToken: UUID?
    @State private var isDetailsPopoverPresented = false
    @State private var isHoveringDetailsPopover = false

    private let indicatorHeight: CGFloat = 20

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    var body: some View {
        HStack(spacing: separatorSpacing) {
            RoundedRectangle(cornerRadius: 3)
                .fill(eventColor)
                .frame(width: 8, height: indicatorHeight)

            HStack(spacing: 6) {
                Text(entry.event.title)
                    .font(textFont)
                    .foregroundStyle(Color.white)
                    .lineLimit(1)

                if let timeText {
                    Text(timeText)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(Color.white.opacity(0.6))
                        .lineLimit(1)
                }
            }
            .layoutPriority(1)

            Spacer(minLength: 12)

            HStack(spacing: separatorSpacing) {
                if let url = linkURL {
                    Button {
                        copyToClipboard(url: url)
                        triggerCopyFeedback()
                    } label: {
                        Image(systemName: didCopyLink ? "checkmark.circle.fill" : "link")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(didCopyLink ? Color.green : Color.white.opacity(0.85))
                            .symbolRenderingMode(.monochrome)
                            .animation(.easeInOut(duration: 0.2), value: didCopyLink)
                    }
                    .buttonStyle(.plain)
                    .help("Copy event link")
                }

                if hasDetails {
                    Button {
                        isDetailsPopoverPresented.toggle()
                    } label: {
                        Image(systemName: "info.circle")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.85))
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $isDetailsPopoverPresented, arrowEdge: .top) {
                        MinimalisticReminderDetailsView(
                            entry: entry,
                            linkURL: linkURL,
                            onHoverChanged: { hovering in
                                isHoveringDetailsPopover = hovering
                                updatePopoverActivity()
                            }
                        )
                        .onDisappear {
                            isHoveringDetailsPopover = false
                            updatePopoverActivity()
                        }
                    }
                    .onChange(of: isDetailsPopoverPresented) { _, presented in
                        if !presented {
                            isHoveringDetailsPopover = false
                            updatePopoverActivity()
                        }
                    }
                }
            }
        }
        .frame(height: ReminderLiveActivityManager.listRowHeight)
        .contentShape(Rectangle())
        .onTapGesture {
            openInCalendar()
        }
        .onDisappear {
            copyResetToken = nil
            didCopyLink = false
            vm.isReminderPopoverActive = false
        }
    }

    private var eventColor: Color {
        Color(nsColor: entry.event.calendar.color).ensureMinimumBrightness(factor: 0.7)
    }

    private var hasDetails: Bool {
        let location = entry.event.location?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let notes = entry.event.notes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !location.isEmpty || !notes.isEmpty
    }

    private var linkURL: URL? {
        entry.event.url ?? entry.event.calendarAppURL()
    }

    private var timeText: String? {
        Self.timeFormatter.string(from: entry.event.start)
    }

    private func updatePopoverActivity() {
        vm.isReminderPopoverActive = isDetailsPopoverPresented && isHoveringDetailsPopover
    }

    private func triggerCopyFeedback() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.65)) {
            didCopyLink = true
        }

        let token = UUID()
        copyResetToken = token

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [token] in
            guard copyResetToken == token else { return }

            withAnimation(.easeInOut(duration: 0.2)) {
                didCopyLink = false
            }

            if copyResetToken == token {
                copyResetToken = nil
            }
        }
    }

    private func copyToClipboard(url: URL) {
#if canImport(AppKit)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(url.absoluteString, forType: .string)
#endif
    }

    private func openInCalendar() {
#if canImport(AppKit)
        guard let url = linkURL else { return }
        NSWorkspace.shared.open(url)
#endif
    }
}

private struct MinimalisticReminderDetailsView: View {
    let entry: ReminderLiveActivityManager.ReminderEntry
    let linkURL: URL?
    var onHoverChanged: (Bool) -> Void = { _ in }

    private let detailFont = Font.system(size: 13, weight: .regular)
    private let smallLabelFont = Font.system(size: 12, weight: .semibold)
    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(entry.event.title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.white)
                .lineLimit(2)

            VStack(alignment: .leading, spacing: 6) {
                if let timeRange = timeRangeText {
                    detailRow(icon: "clock", label: "Time", value: timeRange)
                }

                if let location = entry.event.location, !location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    detailRow(icon: "mappin.and.ellipse", label: "Location", value: location)
                }

                if let notes = entry.event.notes, !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    detailRow(icon: "note.text", label: "Notes", value: notes)
                }
            }

            if let url = linkURL {
                Button {
                    open(url: url)
                } label: {
                    Label("Open in Calendar", systemImage: "arrow.up.right.square")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.link)
                .foregroundStyle(Color.accentColor)
            }
        }
        .padding(16)
        .frame(minWidth: 220)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.black.opacity(0.92))
        )
        .onHover { hovering in
            onHoverChanged(hovering)
        }
        .onDisappear {
            onHoverChanged(false)
        }
    }

    private func detailRow(icon: String, label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(label, systemImage: icon)
                .font(smallLabelFont)
                .foregroundStyle(Color.white.opacity(0.8))
            Text(value)
                .font(detailFont)
                .foregroundStyle(Color.white)
        }
    }

    private var timeRangeText: String? {
        let startText = Self.timeFormatter.string(from: entry.event.start)
        let endText = Self.timeFormatter.string(from: entry.event.end)
        return startText == endText ? startText : "\(startText) – \(endText)"
    }

    private func open(url: URL) {
#if canImport(AppKit)
        NSWorkspace.shared.open(url)
#endif
    }
}
    // MARK: - Visualizer
    
    @Default(.useMusicVisualizer) var useMusicVisualizer
    
    private var visualizer: some View {
        let width = CGFloat(Defaults[.visualizerBarCount]) * 4
        return Rectangle()
            .fill((Defaults[.coloredSpectrogram] ? Color(nsColor: MusicManager.shared.avgColor) : Color.gray).spectrogramGradient())
            .mask {
                AudioVisualizerView(isPlaying: .constant(MusicManager.shared.isPlaying))
                    .frame(width: width, height: 16)
            }
            .frame(width: width, height: 16)
            .matchedGeometryEffect(id: "spectrum", in: albumArtNamespace)
    }
    
    // MARK: - Progress Bar (Full Width)
    
    @ObservedObject var musicManager = MusicManager.shared
    @State private var sliderValue: Double = MusicManager.shared.estimatedPlaybackPosition()
    @State private var dragging: Bool = false
    @State private var lastDragged: Date = .distantPast
    
    /// Whether the progress timeline should be paused (no ticks).
    private var isProgressTimelinePaused: Bool {
        !musicManager.isPlaying || musicManager.isLiveStream || musicManager.playbackRate <= 0
    }

    private var progressBar: some View {
        TimelineView(
            .animation(
                paused: isProgressTimelinePaused
            )
        ) { timeline in
            MusicSliderView(
                sliderValue: $sliderValue,
                duration: Binding(
                    get: { musicManager.songDuration },
                    set: { musicManager.songDuration = $0 }
                ),
                lastDragged: $lastDragged,
                color: musicManager.avgColor,
                dragging: $dragging,
                currentDate: timeline.date,
                timestampDate: musicManager.timestampDate,
                elapsedTime: musicManager.elapsedTime,
                playbackRate: musicManager.playbackRate,
                isPlaying: musicManager.isPlaying,
                isLiveStream: musicManager.isLiveStream,
                onValueChange: { newValue in
                    musicManager.seek(to: newValue)
                },
                labelLayout: .inline,
                trailingLabel: .remaining,
                restingTrackHeight: 7,
                draggingTrackHeight: 11
            )
        }
        .onAppear {
            sliderValue = musicManager.elapsedTime
        }
        .onChange(of: musicManager.isLiveStream) { _, isLive in
            if isLive {
                dragging = false
                sliderValue = 0
            }
        }
    }

    // MARK: - Playback Controls (Larger)
    
    private var playbackControls: some View {
        HStack(spacing: 10) {
            ForEach(Array(displayedSlots.enumerated()), id: \.offset) { _, slot in
                slotView(for: slot)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, 2)
    }

    private var shouldShowControlHUDRow: Bool {
        guard vm.notchState == .open else { return false }
        guard coordinator.sneakPeek.show else { return false }
        guard Defaults[.enableSystemHUD] else { return false }
        guard !Defaults[.enableCustomOSD] && !Defaults[.enableVerticalHUD] && !Defaults[.enableCircularHUD] else { return false }

        switch coordinator.sneakPeek.type {
        case .volume:
            return Defaults[.enableVolumeHUD]
        case .brightness:
            return Defaults[.enableBrightnessHUD]
        case .backlight:
            return Defaults[.enableKeyboardBacklightHUD]
        default:
            return false
        }
    }

    private var controlHUDRow: some View {
        HStack(alignment: .center, spacing: 10) {
            if !controlLeftIconName.isEmpty {
                Image(systemName: controlLeftIconName)
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 22, height: 22, alignment: .center)
            }

            controlHUDSlider

            if !controlRightIconName.isEmpty {
                Image(systemName: controlRightIconName)
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 22, height: 22, alignment: .center)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .frame(height: 60, alignment: .center)
        .onAppear { syncHUDValueIfNeeded(force: true) }
        .onChange(of: coordinator.sneakPeek.value) { _, _ in
            syncHUDValueIfNeeded(force: false)
        }
    }

    private var controlHUDSlider: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            CustomSlider(
                value: Binding(
                    get: { hudValue },
                    set: { newValue in
                        hudValue = newValue
                        updateControlHUDValue(newValue)
                    }
                ),
                range: 0...1,
                color: .white,
                dragging: $hudDragging,
                lastDragged: $hudLastDragged,
                onValueChange: { newValue in
                    updateControlHUDValue(newValue)
                },
                thumbSize: 10,
                restingTrackHeight: 4,
                draggingTrackHeight: 7
            )
            .frame(height: 7)
            Spacer(minLength: 0)
        }
        .frame(height: 22)
    }

    private func syncHUDValueIfNeeded(force: Bool) {
        guard shouldShowControlHUDRow else { return }
        guard force || !hudDragging else { return }
        hudValue = Double(coordinator.sneakPeek.value)
    }

    private func updateControlHUDValue(_ newValue: Double) {
        let clamped = max(0, min(1, newValue))
        switch coordinator.sneakPeek.type {
        case .volume:
            SystemVolumeController.shared.setVolume(Float(clamped))
        case .brightness:
            SystemBrightnessController.shared.setBrightness(Float(clamped))
        case .backlight:
            SystemKeyboardBacklightController.shared.setLevel(Float(clamped))
        default:
            break
        }
    }

    private var controlLeftIconName: String {
        switch coordinator.sneakPeek.type {
        case .volume:
            return SystemVolumeController.shared.isMuted ? "speaker.slash" : "speaker.wave.1"
        case .brightness:
            return "sun.min.fill"
        case .backlight:
            return "light.min"
        default:
            return ""
        }
    }

    private var controlRightIconName: String {
        switch coordinator.sneakPeek.type {
        case .volume:
            return SystemVolumeController.shared.isMuted ? "" : "speaker.wave.3"
        case .brightness:
            return "sun.max.fill"
        case .backlight:
            return "light.max"
        default:
            return ""
        }
    }
    
    private var playPauseButton: some View {
        MinimalisticSquircircleButton(
            icon: musicManager.isPlaying ? (musicManager.isLiveStream ? "stop.fill" : "pause.fill") : "play.fill",
            fontSize: 26,
            fontWeight: .semibold,
            frameSize: CGSize(width: 54, height: 54),
            cornerRadius: 22,
            foregroundColor: .white,
            pressEffect: .none,
            symbolEffectStyle: .replace,
            action: {
                musicManager.togglePlay()
            }
        )
    }
    
    private struct SkipTrigger {
        let token: Int
        let pressEffect: MinimalisticSquircircleButton.PressEffect
    }

    private func controlButton(
        icon: String,
        size: CGFloat = 18,
        isActive: Bool = false,
        activeColor: Color? = nil,
        pressEffect: MinimalisticSquircircleButton.PressEffect = .none,
        symbolEffect: MinimalisticSquircircleButton.SymbolEffectStyle = .none,
        trigger: SkipTrigger? = nil,
        action: @escaping () -> Void
    ) -> some View {
        let resolvedActiveColor = activeColor ?? brandAccentColor
        return MinimalisticSquircircleButton(
            icon: icon,
            fontSize: size,
            fontWeight: .medium,
            frameSize: CGSize(width: 36, height: 36),
            cornerRadius: 14,
            foregroundColor: isActive ? resolvedActiveColor : .white.opacity(0.85),
            pressEffect: pressEffect,
            symbolEffectStyle: symbolEffect,
            externalTriggerToken: trigger?.token,
            externalTriggerEffect: trigger?.pressEffect,
            action: action
        )
    }

    private var displayedSlots: [MusicControlButton] {
        if showCustomControls {
            let normalized = slotConfig.normalized(allowingMediaOutput: showMediaOutputControl, isAppleMusicActive: musicManager.isAppleMusicActive, isSpotifyActive: musicManager.isSpotifyActive)
            return normalized.contains(where: { $0 != .none }) ? normalized : MusicControlButton.defaultLayout
        }

        switch musicSkipBehavior {
        case .track:
            return MusicControlButton.minimalLayout
        case .tenSecond:
            return [.none, .seekBackward, .playPause, .seekForward, .none]
        }
    }

    @ViewBuilder
    private func slotView(for control: MusicControlButton) -> some View {
        switch control {
        case .none:
            Spacer(minLength: 0)
        case .playPause:
            playPauseButton
        case .trackBackward:
            controlButton(
                icon: "backward.fill",
                size: 18,
                pressEffect: .nudge(-skipMagnitude),
                symbolEffect: .replace,
                trigger: skipGestureTrigger(for: .trackBackward),
                action: { musicManager.previousTrack() }
            )
        case .trackForward:
            controlButton(
                icon: "forward.fill",
                size: 18,
                pressEffect: .nudge(skipMagnitude),
                symbolEffect: .replace,
                trigger: skipGestureTrigger(for: .trackForward),
                action: { musicManager.nextTrack() }
            )
        case .seekBackward:
            controlButton(
                icon: "gobackward.10",
                size: 18,
                pressEffect: .wiggle(.counterClockwise),
                symbolEffect: .wiggle,
                trigger: skipGestureTrigger(for: .seekBackward),
                action: { musicManager.seek(by: -seekInterval) }
            )
        case .seekForward:
            controlButton(
                icon: "goforward.10",
                size: 18,
                pressEffect: .wiggle(.clockwise),
                symbolEffect: .wiggle,
                trigger: skipGestureTrigger(for: .seekForward),
                action: { musicManager.seek(by: seekInterval) }
            )
        case .shuffle:
            controlButton(icon: "shuffle", isActive: musicManager.isShuffled) {
                Task { await musicManager.toggleShuffle() }
            }
        case .repeatMode:
            controlButton(icon: repeatIcon, isActive: musicManager.repeatMode != .off, symbolEffect: .replace) {
                Task { await musicManager.toggleRepeat() }
            }
        case .mediaOutput:
            MinimalisticMediaOutputButton()
        case .airPlay:
            MinimalisticAirPlayButton()
        case .lyrics:
            controlButton(
                icon: enableLyrics ? "quote.bubble.fill" : "quote.bubble",
                isActive: enableLyrics,
                activeColor: brandAccentColor,
                symbolEffect: .replace
            ) {
                enableLyrics.toggle()
            }
        case .likeTrack:
            LikeTrackControl { presentation, toggle in
                controlButton(
                    icon: presentation.iconName,
                    isActive: presentation.isActive,
                    activeColor: brandAccentColor,
                    symbolEffect: .replace
                ) {
                    toggle()
                }
            }
        }
    }

    private func skipGestureTrigger(for control: MusicControlButton) -> SkipTrigger? {
        guard let pulse = musicManager.skipGesturePulse else { return nil }

        switch control {
        case .trackBackward where pulse.behavior == .track && pulse.direction == .backward:
            return SkipTrigger(token: pulse.token, pressEffect: .nudge(-skipMagnitude))
        case .trackForward where pulse.behavior == .track && pulse.direction == .forward:
            return SkipTrigger(token: pulse.token, pressEffect: .nudge(skipMagnitude))
        case .seekBackward where pulse.behavior == .tenSecond && pulse.direction == .backward:
            return SkipTrigger(token: pulse.token, pressEffect: .wiggle(.counterClockwise))
        case .seekForward where pulse.behavior == .tenSecond && pulse.direction == .forward:
            return SkipTrigger(token: pulse.token, pressEffect: .wiggle(.clockwise))
        default:
            return nil
        }
    }
    private struct MinimalisticMediaOutputButton: View {
        @ObservedObject private var routeManager = AudioRouteManager.shared
        @StateObject private var volumeModel = MediaOutputVolumeViewModel()
        @EnvironmentObject private var vm: DynamicIslandViewModel
        @State private var isPopoverPresented = false
        @State private var popoverToken = UUID()

        var body: some View {
            MinimalisticSquircircleButton(
                icon: routeManager.activeDevice?.iconName ?? "speaker.wave.2",
                fontSize: 18,
                fontWeight: .medium,
                frameSize: CGSize(width: 36, height: 36),
                cornerRadius: 14,
                foregroundColor: .white.opacity(0.85),
                symbolEffectStyle: .replace
            ) {
                isPopoverPresented.toggle()
                if isPopoverPresented {
                    routeManager.refreshDevices()
                }
            }
            .accessibilityLabel("Media output")
            .popover(isPresented: $isPopoverPresented, arrowEdge: .bottom) {
                MediaOutputSelectorPopover(
                    routeManager: routeManager,
                    volumeModel: volumeModel,
                    onHoverChanged: { _ in }
                ) {
                    isPopoverPresented = false
                    updateActivity()
                }
            }
            .onChange(of: isPopoverPresented) { _, _ in
                updateActivity()
            }
            .onAppear {
                routeManager.refreshDevices()
            }
            .onDisappear {
                vm.setMediaOutputPopoverActive(false, token: popoverToken)
            }
        }

        /// Reports whether this picker's popover is open, so the notch knows not
        /// to auto-close while it is. Keyed by a token unique to this presenter,
        /// so one picker closing does not clear the flag for another still open.
        private func updateActivity() {
            // Presentation alone -- see MediaOutputPickerButton: also requiring
            // hover let the notch auto-close while the pointer was over the
            // popover, which is a separate window.
            vm.setMediaOutputPopoverActive(isPopoverPresented, token: popoverToken)
        }
    }

    private struct MinimalisticAirPlayButton: View {
        @ObservedObject private var musicManager = MusicManager.shared
        @ObservedObject private var airPlayManager = AppleMusicAirPlayManager.shared
        @EnvironmentObject private var vm: DynamicIslandViewModel
        @State private var isPopoverPresented = false
        @State private var popoverToken = UUID()

        private var isAppleMusicActive: Bool {
            musicManager.bundleIdentifier == "com.apple.Music"
        }

        var body: some View {
            MinimalisticSquircircleButton(
                icon: "airplayaudio",
                fontSize: 18,
                fontWeight: .medium,
                frameSize: CGSize(width: 36, height: 36),
                cornerRadius: 14,
                foregroundColor: .white.opacity(0.85),
                symbolEffectStyle: .replace
            ) {
                isPopoverPresented.toggle()
                if isPopoverPresented {
                    Task { await airPlayManager.refreshDevices() }
                }
            }
            .accessibilityLabel("AirPlay")
            .popover(isPresented: $isPopoverPresented, arrowEdge: .bottom) {
                AirPlaySelectorPopover(
                    airPlayManager: airPlayManager,
                    onHoverChanged: { _ in }
                ) {
                    isPopoverPresented = false
                    updateActivity()
                }
            }
            .onChange(of: isPopoverPresented) { _, _ in
                updateActivity()
            }
            .onAppear {
                if isAppleMusicActive {
                    Task { await airPlayManager.refreshDevices() }
                }
            }
            .onChange(of: musicManager.bundleIdentifier) { _, newBundle in
                if newBundle == "com.apple.Music" {
                    Task { await airPlayManager.refreshDevices() }
                }
            }
            .onDisappear {
                vm.setMediaOutputPopoverActive(false, token: popoverToken)
            }
        }

        /// Reports whether this picker's popover is open, so the notch knows not
        /// to auto-close while it is. Keyed by a token unique to this presenter,
        /// so one picker closing does not clear the flag for another still open.
        private func updateActivity() {
            // Presentation alone -- see MediaOutputPickerButton: also requiring
            // hover let the notch auto-close while the pointer was over the
            // popover, which is a separate window.
            vm.setMediaOutputPopoverActive(isPopoverPresented, token: popoverToken)
        }
    }

    private var repeatIcon: String {
        switch musicManager.repeatMode {
        case .off: return "repeat"
        case .all: return "repeat"
        case .one: return "repeat.1"
        }
    }
}

// MARK: - Minimalistic Album Art

struct MinimalisticAlbumArtView: View {
    @ObservedObject var musicManager = MusicManager.shared
    @ObservedObject var vm: DynamicIslandViewModel
    @Default(.showLiveCanvasInDynamicIsland) private var showLiveCanvasInDynamicIsland
    let albumArtNamespace: Namespace.ID

    private var usesLiveCanvasArtwork: Bool {
        showLiveCanvasInDynamicIsland && musicManager.videoArtworkURL != nil
    }

    private var albumArtCornerRadius: CGFloat {
        musicManager.albumArt.size.width / musicManager.albumArt.size.height > 1.0 ? 4 : 12
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if Defaults[.lightingEffect] {
                albumArtBackground
            }
            albumArtButton
        }
    }
    
    private var albumArtBackground: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .background(
                DynamicIslandArtworkSourceView(
                    cornerRadius: albumArtCornerRadius,
                    contentMode: .fill
                )
            )
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: albumArtCornerRadius))
            .scaleEffect(x: 1.04, y: 1.05)
            .rotationEffect(.degrees(92))
            .blur(radius: 14)
            .opacity(
                usesLiveCanvasArtwork
                    ? (musicManager.isPlaying ? 0.35 : 0.12)
                    : min(0.28, 1 - max(musicManager.albumArt.getBrightness(), 0.3))
            )
            .shadow(
                color: Color(nsColor: musicManager.avgColor).opacity(usesLiveCanvasArtwork ? 0.14 : 0.08),
                radius: usesLiveCanvasArtwork ? 6 : 4,
                x: 0,
                y: 0
            )
    }
    
    private var albumArtButton: some View {
        Button {
            musicManager.openMusicApp()
        } label: {
                Color.clear
                    .aspectRatio(1, contentMode: .fit)
                    .background(
                        DynamicIslandArtworkSourceView(
                            cornerRadius: albumArtCornerRadius,
                            contentMode: .fit
                        )
                    )
                    .clipped()
                    .matchedGeometryEffect(id: "albumArt", in: albumArtNamespace)
                    .albumArtFlip(angle: musicManager.flipAngle)
                    .parallax3D()
        }
        .buttonStyle(PlainButtonStyle())
        .opacity(musicManager.isPlaying ? 1 : 0.4)
        .scaleEffect(musicManager.isPlaying ? 1 : 0.85)
    }
}

// MARK: - Hover-highlighted control button

private struct MinimalisticSquircircleButton: View {
    let icon: String
    let fontSize: CGFloat
    let fontWeight: Font.Weight
    let frameSize: CGSize
    let cornerRadius: CGFloat
    let foregroundColor: Color
    let pressEffect: PressEffect
    let symbolEffectStyle: SymbolEffectStyle
    let externalTriggerToken: Int?
    let externalTriggerEffect: PressEffect?
    let action: () -> Void

    @State private var isHovering = false
    @State private var pressOffset: CGFloat = 0
    @State private var rotationAngle: Double = 0
    @State private var wiggleToken: Int = 0
    @State private var lastExternalTriggerToken: Int?

    init(
        icon: String,
        fontSize: CGFloat,
        fontWeight: Font.Weight,
        frameSize: CGSize,
        cornerRadius: CGFloat,
        foregroundColor: Color,
        pressEffect: PressEffect = .none,
        symbolEffectStyle: SymbolEffectStyle = .none,
        externalTriggerToken: Int? = nil,
        externalTriggerEffect: PressEffect? = nil,
        action: @escaping () -> Void
    ) {
        self.icon = icon
        self.fontSize = fontSize
        self.fontWeight = fontWeight
        self.frameSize = frameSize
        self.cornerRadius = cornerRadius
        self.foregroundColor = foregroundColor
        self.pressEffect = pressEffect
        self.symbolEffectStyle = symbolEffectStyle
        self.externalTriggerToken = externalTriggerToken
        self.externalTriggerEffect = externalTriggerEffect
        self.action = action
    }

    var body: some View {
        Button {
            triggerPressEffect()
            action()
        } label: {
            iconView()
                .frame(width: frameSize.width, height: frameSize.height)
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(isHovering ? Color.white.opacity(0.18) : .clear)
                )
                .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
        .buttonStyle(PlainButtonStyle())
        .offset(x: pressOffset)
        .rotationEffect(.degrees(rotationAngle))
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.18)) {
                isHovering = hovering
            }
        }
        .onChange(of: externalTriggerToken) { _, newToken in
            guard let newToken, newToken != lastExternalTriggerToken else { return }
            lastExternalTriggerToken = newToken
            triggerPressEffect(override: externalTriggerEffect)
        }
    }

    private func triggerPressEffect(override: PressEffect? = nil) {
        let effect = override ?? pressEffect

        switch effect {
        case .none:
            return
        case .nudge(let amount):
            withAnimation(.spring(response: 0.16, dampingFraction: 0.72)) {
                pressOffset = amount
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                withAnimation(.spring(response: 0.26, dampingFraction: 0.8)) {
                    pressOffset = 0
                }
            }
        case .wiggle(let direction):
            guard #available(macOS 14.0, *) else { return }
            wiggleToken += 1
            let angle: Double = direction == .clockwise ? 11 : -11

            withAnimation(.spring(response: 0.18, dampingFraction: 0.52)) {
                rotationAngle = angle
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.76)) {
                    rotationAngle = 0
                }
            }
        }
    }

    @ViewBuilder
    private func iconView() -> some View {
        let image = Image(systemName: icon)
            .font(.system(size: fontSize, weight: fontWeight))
            .foregroundColor(foregroundColor)

        switch symbolEffectStyle {
        case .none:
            image
        case .replace:
            if #available(macOS 14.0, *) {
                image.contentTransition(.symbolEffect(.replace))
            } else {
                image
            }
        case .bounce:
            if #available(macOS 14.0, *) {
                image.symbolEffect(.bounce, value: icon)
            } else {
                image
            }
        case .replaceAndBounce:
            if #available(macOS 14.0, *) {
                image
                    .contentTransition(.symbolEffect(.replace))
                    .symbolEffect(.bounce, value: icon)
            } else {
                image
            }
        case .wiggle:
            if #available(macOS 15.0, *) {
                image.symbolEffect(
                    .wiggle.byLayer,
                    options: .nonRepeating,
                    value: wiggleToken
                )
            } else {
                image
            }
        }
    }

    enum PressEffect {
        case none
        case nudge(CGFloat)
        case wiggle(WiggleDirection)
    }

    enum SymbolEffectStyle {
        case none
        case replace
        case bounce
        case replaceAndBounce
        case wiggle
    }

    enum WiggleDirection {
        case clockwise
        case counterClockwise
    }
}
