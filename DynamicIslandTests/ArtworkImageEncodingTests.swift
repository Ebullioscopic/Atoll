/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

import AppKit
import XCTest
@testable import Atoll

final class ArtworkImageEncodingTests: XCTestCase {
    private func solidImage(pixels: Int, color: NSColor) -> NSBitmapImageRep {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        )!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        color.setFill()
        NSRect(x: 0, y: 0, width: pixels, height: pixels).fill()
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }

    func testMultiRepresentationIconEncodesOnlyLargestBoundedBitmap() throws {
        let image = NSImage(size: NSSize(width: 32, height: 32))
        for pixels in [16, 32, 64, 128, 256, 512, 1024, 4096] {
            image.addRepresentation(solidImage(pixels: pixels, color: .systemRed))
        }

        let cgImage = try XCTUnwrap(ArtworkImageEncoding.cgImage(from: image))
        XCTAssertEqual(cgImage.width, Int(ArtworkImageEncoding.maxPixelDimension))

        let png = try XCTUnwrap(ArtworkImageEncoding.pngData(from: image))
        let decoded = try XCTUnwrap(NSBitmapImageRep(data: png))
        XCTAssertEqual(decoded.pixelsWide, Int(ArtworkImageEncoding.maxPixelDimension))
    }

    func testFingerprintIsStableAndDistinguishesArtwork() {
        let red = NSImage(size: NSSize(width: 300, height: 300))
        red.addRepresentation(solidImage(pixels: 300, color: .systemRed))
        let sameRed = NSImage(size: NSSize(width: 300, height: 300))
        sameRed.addRepresentation(solidImage(pixels: 300, color: .systemRed))
        let blue = NSImage(size: NSSize(width: 300, height: 300))
        blue.addRepresentation(solidImage(pixels: 300, color: .systemBlue))

        XCTAssertNotNil(ArtworkImageEncoding.fingerprint(for: red))
        XCTAssertEqual(ArtworkImageEncoding.fingerprint(for: red), ArtworkImageEncoding.fingerprint(for: sameRed))
        XCTAssertNotEqual(ArtworkImageEncoding.fingerprint(for: red), ArtworkImageEncoding.fingerprint(for: blue))
    }
}
