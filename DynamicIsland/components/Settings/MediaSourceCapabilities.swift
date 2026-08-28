//
//  MediaSourceCapabilities.swift
//  DynamicIsland
//
//  What each media source can actually be driven to do, for the ⓘ beside the
//  source picker.
//

import SwiftUI

/// How well a source supports one control.
///
/// `readOnly` is its own case rather than a flag because it is the answer that
/// surprises people: TIDAL reports whether a song is favourited and offers no
/// way to change it, so the heart is shown filled-in and refuses the click.
/// Saying "no" there would be wrong, and saying "yes" would be worse.
enum MediaSourceSupport: Equatable {
    case full
    case readOnly
    case none

    var symbol: String {
        switch self {
        case .full:     return "checkmark.circle.fill"
        case .readOnly: return "eye.circle.fill"
        case .none:     return "xmark.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .full:     return .green
        case .readOnly: return .orange
        case .none:     return .secondary
        }
    }

    var label: String {
        switch self {
        case .full:     return String(localized: "Yes")
        case .readOnly: return String(localized: "Read only")
        case .none:     return String(localized: "No")
        }
    }
}

struct MediaSourceCapability: Identifiable {
    let name: String
    let favoriting: MediaSourceSupport
    let shuffle: MediaSourceSupport
    let repeatMode: MediaSourceSupport
    /// One line on *how*, because "no" without a reason reads as an oversight
    /// rather than as something that was checked.
    let note: String

    var id: String { name }
}

enum MediaSourceCapabilities {
    static func entry(for type: MediaControllerType) -> MediaSourceCapability {
        switch type {
        case .nowPlaying:
            return .init(name: String(localized: "Now Playing"),
                         favoriting: .full, shuffle: .full, repeatMode: .full,
                         note: String(localized: "Follows whichever app is playing, so it can do whatever that app can."))
        case .appleMusic:
            return .init(name: String(localized: "Apple Music"),
                         favoriting: .full, shuffle: .full, repeatMode: .full,
                         note: String(localized: "AppleScript on Music.app. No subscription needed."))
        case .spotify:
            return .init(name: String(localized: "Spotify"),
                         favoriting: .full, shuffle: .full, repeatMode: .full,
                         note: String(localized: "Favouriting uses the Spotify account connected in settings; Spotify's own app offers no local way to do it."))
        case .youtubeMusic:
            return .init(name: String(localized: "YouTube Music"),
                         favoriting: .full, shuffle: .full, repeatMode: .full,
                         note: String(localized: "The th-ch desktop app's local API server, which Atoll is already authenticated with."))
        case .tidal:
            return .init(name: String(localized: "TIDAL"),
                         favoriting: .readOnly, shuffle: .full, repeatMode: .full,
                         note: String(localized: "TIDAL exposes no way to set a favourite, so the heart shows the state but cannot be clicked. Shuffle and repeat go through the Playback menu."))
        case .cider:
            return .init(name: String(localized: "Cider"),
                         favoriting: .full, shuffle: .full, repeatMode: .full,
                         note: String(localized: "Cider's own local API, which needs the app token entered below."))
        case .amazonMusic:
            return .init(name: String(localized: "Amazon Music"),
                         favoriting: .none, shuffle: .full, repeatMode: .full,
                         note: String(localized: "Amazon Music ships no scripting dictionary, and the system media interface has no way to favourite."))
        }
    }

    static var all: [MediaSourceCapability] {
        MediaControllerType.allCases.map(entry(for:))
    }
}

/// The ⓘ beside the source picker.
struct MediaSourceCapabilitiesButton: View {
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            Image(systemName: "info.circle")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .help("What each source supports")
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            MediaSourceCapabilitiesTable()
        }
    }
}

struct MediaSourceCapabilitiesTable: View {
    private let columnWidth: CGFloat = 74

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("What each source supports")
                .font(.system(size: 13, weight: .semibold))

            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    Text("Source")
                        .frame(width: 120, alignment: .leading)
                    ForEach([String(localized: "Favorite"),
                             String(localized: "Shuffle"),
                             String(localized: "Repeat")], id: \.self) { title in
                        Text(title).frame(width: columnWidth)
                    }
                }
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.bottom, 6)

                ForEach(MediaSourceCapabilities.all) { row in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 0) {
                            Text(row.name)
                                .font(.system(size: 12, weight: .medium))
                                .frame(width: 120, alignment: .leading)
                            cell(row.favoriting)
                            cell(row.shuffle)
                            cell(row.repeatMode)
                        }
                        Text(row.note)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.vertical, 6)

                    if row.id != MediaSourceCapabilities.all.last?.id {
                        Divider().opacity(0.4)
                    }
                }
            }

            HStack(spacing: 14) {
                legend(.full, String(localized: "Supported"))
                legend(.readOnly, String(localized: "Shows state, cannot change it"))
                legend(.none, String(localized: "Not available"))
            }
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(width: 420)
    }

    private func cell(_ support: MediaSourceSupport) -> some View {
        Image(systemName: support.symbol)
            .font(.system(size: 12))
            .foregroundStyle(support.tint)
            .frame(width: columnWidth)
            .accessibilityLabel(support.label)
    }

    private func legend(_ support: MediaSourceSupport, _ text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: support.symbol)
                .font(.system(size: 9))
                .foregroundStyle(support.tint)
            Text(text)
        }
    }
}
