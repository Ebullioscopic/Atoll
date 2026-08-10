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

import Foundation
import UniformTypeIdentifiers

/// One conversion the user can pick from the Shelf's "Convert To" submenu.
struct ShelfConversionTarget: Equatable, Hashable, Sendable {
    /// How the conversion is carried out. Kept explicit so the service never has
    /// to re-derive intent from the file type.
    enum Route: Equatable, Hashable, Sendable {
        /// ImageIO re-encode.
        case image
        /// A single-page PDF built from an image.
        case imageToPDF
        /// AVAssetExportSession remux/transcode of a movie.
        case movie
        /// AVAssetExportSession export of the audio track only.
        case audio
        /// NSAttributedString read/write between rich-text formats.
        case document
        /// PDFKit output built from an attributed string.
        case documentToPDF
    }

    let type: UTType
    let route: Route
    /// Menu title, e.g. "PNG" or "M4A (Audio Only)".
    let title: String

    var fileExtension: String {
        type.preferredFilenameExtension ?? "dat"
    }
}

/// What a "Convert To" menu item carries, so the handler never has to re-derive
/// the user's choice from a menu title.
struct ShelfConversionRequest: Sendable {
    let sourceURL: URL
    let target: ShelfConversionTarget
}

/// Decides which conversions are offered for a given source type.
///
/// The whole point is that the menu never shows a conversion that would fail:
/// everything here is reachable with the frameworks already linked (ImageIO,
/// AVFoundation, AppKit's attributed strings, PDFKit) — no external tools, no
/// bundled binaries.
enum ShelfConversionMatrix {

    // MARK: - Supported target sets

    private static let imageTargets: [(UTType, String)] = [
        (.png, "PNG"),
        (.jpeg, "JPEG"),
        (.heic, "HEIC"),
        (.tiff, "TIFF")
    ]

    private static let movieTargets: [(UTType, String)] = [
        (.mpeg4Movie, "MP4"),
        (.quickTimeMovie, "MOV")
    ]

    private static let audioTargets: [(UTType, String)] = [
        (.mpeg4Audio, "M4A"),
        (.wav, "WAV"),
        (.aiff, "AIFF")
    ]

    private static let documentTargets: [(UTType, String)] = [
        (.rtf, "RTF"),
        (.html, "HTML"),
        (.plainText, "Plain Text")
    ]

    /// Formats AVFoundation can read but this matrix will not write, so they only
    /// ever appear as a source. WebP and DOCX are read-only for the same reason.
    static func targets(for source: UTType) -> [ShelfConversionTarget] {
        if source.conforms(to: .image) {
            var targets = imageTargets
                .filter { $0.0 != source }
                .map { ShelfConversionTarget(type: $0.0, route: .image, title: $0.1) }
            targets.append(ShelfConversionTarget(type: .pdf, route: .imageToPDF, title: "PDF"))
            return targets
        }

        if source.conforms(to: .movie) || source.conforms(to: .video) {
            var targets = movieTargets
                .filter { $0.0 != source }
                .map { ShelfConversionTarget(type: $0.0, route: .movie, title: $0.1) }
            // Pulling the audio out of a video is the conversion people actually
            // reach for, so it is offered alongside the container changes.
            targets.append(ShelfConversionTarget(type: .mpeg4Audio, route: .audio, title: "M4A (Audio Only)"))
            return targets
        }

        if source.conforms(to: .audio) {
            return audioTargets
                .filter { $0.0 != source }
                .map { ShelfConversionTarget(type: $0.0, route: .audio, title: $0.1) }
        }

        if isDocument(source) {
            var targets = documentTargets
                .filter { $0.0 != source }
                .map { ShelfConversionTarget(type: $0.0, route: .document, title: $0.1) }
            if source != .pdf {
                targets.append(ShelfConversionTarget(type: .pdf, route: .documentToPDF, title: "PDF"))
            }
            return targets
        }

        return []
    }

    /// Rich-text sources AppKit can read. PDF is excluded: `NSAttributedString`
    /// cannot read it, so a PDF has nothing to convert to here.
    private static func isDocument(_ source: UTType) -> Bool {
        let readable: [UTType] = [.rtf, .rtfd, .html, .plainText, .utf8PlainText]
        if readable.contains(where: { source == $0 || source.conforms(to: $0) }) { return true }
        // DOCX is read-only input; identifier-matched because there is no
        // first-party UTType constant for it.
        return source.identifier == "org.openxmlformats.wordprocessingml.document"
    }
}
