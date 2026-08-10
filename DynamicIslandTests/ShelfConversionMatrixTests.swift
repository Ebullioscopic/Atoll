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

import UniformTypeIdentifiers
import XCTest
@testable import Atoll

/// The matrix is the promise that the Shelf never offers a conversion that would
/// fail, so it is worth testing exhaustively — and it is pure, so it can be.
final class ShelfConversionMatrixTests: XCTestCase {

    private func types(for source: UTType) -> Set<UTType> {
        Set(ShelfConversionMatrix.targets(for: source).map(\.type))
    }

    private func routes(for source: UTType) -> Set<ShelfConversionTarget.Route> {
        Set(ShelfConversionMatrix.targets(for: source).map(\.route))
    }

    // MARK: - Images

    func testImageOffersTheOtherImageFormatsAndPDF() {
        XCTAssertEqual(types(for: .png), [.jpeg, .heic, .tiff, .pdf])
    }

    func testHEICOffersTheOtherImageFormats() {
        XCTAssertEqual(types(for: .heic), [.png, .jpeg, .tiff, .pdf])
    }

    /// WebP can be read but not written here, so it is a source only — it gets
    /// the full writable set and never appears as a target.
    func testWebPIsASourceOnly() {
        XCTAssertEqual(types(for: .webP), [.png, .jpeg, .heic, .tiff, .pdf])
        for source in [UTType.png, .jpeg, .heic, .tiff] {
            XCTAssertFalse(types(for: source).contains(.webP), "WebP must never be offered as a target")
        }
    }

    func testAnImagePDFTargetUsesThePDFRoute() {
        let pdfTarget = ShelfConversionMatrix.targets(for: .png).first { $0.type == .pdf }
        XCTAssertEqual(pdfTarget?.route, .imageToPDF)
    }

    // MARK: - Video

    func testMovieOffersTheOtherContainerAndAudioExtraction() {
        XCTAssertEqual(types(for: .quickTimeMovie), [.mpeg4Movie, .mpeg4Audio])
    }

    func testMP4OffersMOVAndAudioExtraction() {
        XCTAssertEqual(types(for: .mpeg4Movie), [.quickTimeMovie, .mpeg4Audio])
    }

    func testAudioExtractionFromAVideoUsesTheAudioRoute() {
        let target = ShelfConversionMatrix.targets(for: .mpeg4Movie).first { $0.type == .mpeg4Audio }
        XCTAssertEqual(target?.route, .audio)
        XCTAssertEqual(target?.title, "M4A (Audio Only)")
    }

    // MARK: - Audio

    func testAudioOffersTheOtherAudioFormatsOnly() {
        XCTAssertEqual(types(for: .wav), [.mpeg4Audio, .aiff])
        XCTAssertEqual(routes(for: .wav), [.audio])
    }

    func testAudioNeverOffersAVideoContainer() {
        let audioTargets = types(for: .mpeg4Audio)
        XCTAssertFalse(audioTargets.contains(.mpeg4Movie))
        XCTAssertFalse(audioTargets.contains(.quickTimeMovie))
    }

    // MARK: - Documents

    func testRichTextOffersTheOtherTextFormatsAndPDF() {
        XCTAssertEqual(types(for: .rtf), [.html, .plainText, .pdf])
    }

    func testPlainTextOffersRichTextAndPDF() {
        XCTAssertEqual(types(for: .plainText), [.rtf, .html, .pdf])
    }

    func testDOCXIsASourceOnly() {
        guard let docx = UTType("org.openxmlformats.wordprocessingml.document") else {
            return XCTFail("DOCX type identifier no longer resolves")
        }
        XCTAssertEqual(types(for: docx), [.rtf, .html, .plainText, .pdf])
        for source in [UTType.rtf, .html, .plainText] {
            XCTAssertFalse(types(for: source).contains(docx), "DOCX must never be offered as a target")
        }
    }

    /// NSAttributedString cannot read a PDF, so a PDF on the Shelf has nothing to
    /// convert to and the submenu must not appear at all.
    func testPDFOffersNothing() {
        XCTAssertTrue(ShelfConversionMatrix.targets(for: .pdf).isEmpty)
    }

    // MARK: - Invariants

    func testASourceIsNeverOfferedAsItsOwnTarget() {
        let sources: [UTType] = [.png, .jpeg, .heic, .tiff, .quickTimeMovie, .mpeg4Movie,
                                 .mpeg4Audio, .wav, .aiff, .rtf, .html, .plainText]
        for source in sources {
            XCTAssertFalse(types(for: source).contains(source), "\(source.identifier) offered itself")
        }
    }

    func testUnsupportedTypesOfferNothing() {
        for source in [UTType.zip, .folder, .executable, .json] {
            XCTAssertTrue(ShelfConversionMatrix.targets(for: source).isEmpty,
                          "\(source.identifier) should offer no conversions")
        }
    }

    func testEveryTargetHasAUsableFileExtensionAndTitle() {
        let sources: [UTType] = [.png, .quickTimeMovie, .wav, .rtf]
        for source in sources {
            for target in ShelfConversionMatrix.targets(for: source) {
                XCTAssertFalse(target.title.isEmpty)
                XCTAssertFalse(target.fileExtension.isEmpty)
                XCTAssertNotEqual(target.fileExtension, "dat",
                                  "\(target.type.identifier) has no preferred extension")
            }
        }
    }

    func testTargetsAreUniquePerSource() {
        for source in [UTType.png, .mpeg4Movie, .wav, .rtf] {
            let targets = ShelfConversionMatrix.targets(for: source)
            XCTAssertEqual(Set(targets).count, targets.count, "duplicate target for \(source.identifier)")
        }
    }
}
