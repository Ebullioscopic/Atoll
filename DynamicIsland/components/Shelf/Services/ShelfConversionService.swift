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

import AVFoundation
import AppKit
import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers

enum ShelfConversionError: LocalizedError {
    case unreadableSource
    case unsupportedConversion
    case noAudioTrack
    case exportFailed(String)
    case writeFailed

    var errorDescription: String? {
        switch self {
        case .unreadableSource:
            return String(localized: "Atoll could not read that file.")
        case .unsupportedConversion:
            return String(localized: "That conversion is not supported.")
        case .noAudioTrack:
            return String(localized: "That video has no audio track to extract.")
        case .exportFailed(let reason):
            return reason
        case .writeFailed:
            return String(localized: "Atoll could not write the converted file.")
        }
    }
}

/// Converts a file already on the Shelf to another format using only the
/// frameworks the app already links. The source file is never modified or
/// deleted; every result is written to a fresh temporary location.
enum ShelfConversionService {

    static func convert(_ source: URL, to target: ShelfConversionTarget) async throws -> URL {
        let destination = try makeDestination(for: source, target: target)

        switch target.route {
        case .image:
            try convertImage(source, to: destination, type: target.type)
        case .imageToPDF:
            try convertImageToPDF(source, to: destination)
        case .movie:
            try await exportAsset(source, to: destination, type: target.type, audioOnly: false)
        case .audio:
            try await exportAsset(source, to: destination, type: target.type, audioOnly: true)
        case .document:
            try convertDocument(source, to: destination, type: target.type)
        case .documentToPDF:
            try convertDocumentToPDF(source, to: destination)
        }

        return destination
    }

    // MARK: - Destination

    /// Keeps the original basename so the converted item is still recognisable,
    /// in its own temp directory so two conversions of the same file cannot
    /// collide.
    private static func makeDestination(for source: URL, target: ShelfConversionTarget) throws -> URL {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("shelf_convert_\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            throw ShelfConversionError.writeFailed
        }
        return directory
            .appendingPathComponent(source.deletingPathExtension().lastPathComponent)
            .appendingPathExtension(target.fileExtension)
    }

    // MARK: - Images

    private static func convertImage(_ source: URL, to destination: URL, type: UTType) throws {
        guard let imageSource = CGImageSourceCreateWithURL(source as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(imageSource, 0, nil)
        else { throw ShelfConversionError.unreadableSource }

        guard let imageDestination = CGImageDestinationCreateWithURL(
            destination as CFURL,
            type.identifier as CFString,
            1,
            nil
        ) else { throw ShelfConversionError.unsupportedConversion }

        // Carry the source metadata across, then apply the requested quality. JPEG
        // and HEIC are the only lossy targets here, so the setting is harmless
        // elsewhere.
        var properties: [CFString: Any] = [:]
        if let sourceProperties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any] {
            properties = sourceProperties
        }
        properties[kCGImageDestinationLossyCompressionQuality] = 0.9

        CGImageDestinationAddImage(imageDestination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(imageDestination) else {
            throw ShelfConversionError.writeFailed
        }
    }

    private static func convertImageToPDF(_ source: URL, to destination: URL) throws {
        guard let image = NSImage(contentsOf: source) else {
            throw ShelfConversionError.unreadableSource
        }
        let pdf = PDFDocument()
        guard let page = PDFPage(image: image) else {
            throw ShelfConversionError.unsupportedConversion
        }
        pdf.insert(page, at: 0)
        guard pdf.write(to: destination) else {
            throw ShelfConversionError.writeFailed
        }
    }

    // MARK: - Audio and video

    private static func exportAsset(
        _ source: URL,
        to destination: URL,
        type: UTType,
        audioOnly: Bool
    ) async throws {
        let asset = AVURLAsset(url: source)

        if audioOnly {
            let audioTracks = try await asset.loadTracks(withMediaType: .audio)
            guard !audioTracks.isEmpty else { throw ShelfConversionError.noAudioTrack }
        }

        let preset = audioOnly ? AVAssetExportPresetAppleM4A : AVAssetExportPresetPassthrough
        guard let session = AVAssetExportSession(asset: asset, presetName: preset) else {
            throw ShelfConversionError.unsupportedConversion
        }

        let outputType = AVFileType(type.identifier)
        let supported = session.supportedFileTypes
        guard supported.contains(outputType) else {
            // Passthrough cannot always remux into the requested container; fall
            // back to a transcode rather than failing the user's conversion.
            guard !audioOnly,
                  let transcoder = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality),
                  transcoder.supportedFileTypes.contains(outputType)
            else { throw ShelfConversionError.unsupportedConversion }
            try await run(transcoder, to: destination, as: outputType)
            return
        }

        try await run(session, to: destination, as: outputType)
    }

    private static func run(
        _ session: AVAssetExportSession,
        to destination: URL,
        as outputType: AVFileType
    ) async throws {
        if #available(macOS 15.0, *) {
            do {
                try await session.export(to: destination, as: outputType)
            } catch {
                throw ShelfConversionError.exportFailed(error.localizedDescription)
            }
        } else {
            session.outputURL = destination
            session.outputFileType = outputType
            await session.export()
            if session.status != .completed {
                throw ShelfConversionError.exportFailed(
                    session.error?.localizedDescription ?? String(localized: "The export did not finish.")
                )
            }
        }
    }

    // MARK: - Documents

    private static func readDocument(_ source: URL) throws -> NSAttributedString {
        guard let text = try? NSAttributedString(
            url: source,
            options: [.documentType: documentType(for: source)],
            documentAttributes: nil
        ) else { throw ShelfConversionError.unreadableSource }
        return text
    }

    private static func documentType(for source: URL) -> NSAttributedString.DocumentType {
        switch source.pathExtension.lowercased() {
        case "rtf": return .rtf
        case "rtfd": return .rtfd
        case "html", "htm": return .html
        case "doc", "docx": return .docFormat
        default: return .plain
        }
    }

    private static func convertDocument(_ source: URL, to destination: URL, type: UTType) throws {
        let text = try readDocument(source)
        let range = NSRange(location: 0, length: text.length)

        let outputType: NSAttributedString.DocumentType
        switch type {
        case .rtf: outputType = .rtf
        case .html: outputType = .html
        default: outputType = .plain
        }

        guard let data = try? text.data(
            from: range,
            documentAttributes: [.documentType: outputType]
        ) else { throw ShelfConversionError.unsupportedConversion }

        do {
            try data.write(to: destination)
        } catch {
            throw ShelfConversionError.writeFailed
        }
    }

    private static func convertDocumentToPDF(_ source: URL, to destination: URL) throws {
        let text = try readDocument(source)

        // Lay the text out on US Letter pages through an off-screen text view,
        // which is the only way AppKit will paginate an attributed string.
        let pageSize = NSSize(width: 612, height: 792)
        let inset: CGFloat = 36
        let textView = NSTextView(frame: NSRect(
            x: 0, y: 0,
            width: pageSize.width - inset * 2,
            height: pageSize.height - inset * 2
        ))
        textView.textStorage?.setAttributedString(text)

        guard let printInfo = NSPrintInfo.shared.copy() as? NSPrintInfo else {
            throw ShelfConversionError.writeFailed
        }
        printInfo.paperSize = pageSize
        printInfo.topMargin = inset
        printInfo.bottomMargin = inset
        printInfo.leftMargin = inset
        printInfo.rightMargin = inset
        printInfo.jobDisposition = .save
        printInfo.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = destination

        let operation = NSPrintOperation(view: textView, printInfo: printInfo)
        operation.showsPrintPanel = false
        operation.showsProgressPanel = false
        guard operation.run() else { throw ShelfConversionError.writeFailed }
    }
}
