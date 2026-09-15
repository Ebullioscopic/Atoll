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

import SwiftUI
import AppKit
import Cocoa
import Foundation
import Defaults
import CoreImage
import CoreGraphics
import CoreImage.CIFilterBuiltins

extension NSImage {

    /// A copy whose declared point size fits inside a `side`x`side` square, aspect preserved.
    ///
    /// Needed wherever an icon sits in a menu-style `Picker`: rendering the selected row into
    /// the `NSPopUpButton` title drops SwiftUI's `.frame(width:height:)` but keeps
    /// `.resizable()`, so a resizable icon stretches to the button's full width (the AirDrop
    /// icon rendered as a flat wide smear). An image carrying its own size needs neither
    /// modifier and draws identically in the menu and in the button.
    func fitted(toSide side: CGFloat) -> NSImage {
        guard size.width > 0, size.height > 0, let copy = copy() as? NSImage else { return self }
        let scale = min(side / size.width, side / size.height)
        copy.size = NSSize(width: size.width * scale, height: size.height * scale)
        return copy
    }

    func averageColor(completion: @escaping (NSColor?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            guard let cgImage = self.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                DispatchQueue.main.async {
                    completion(nil)
                }
                return
            }
            
            let width = cgImage.width
            let height = cgImage.height
            let totalPixels = width * height
            
            guard let context = CGContext(data: nil,
                                          width: width,
                                          height: height,
                                          bitsPerComponent: 8,
                                          bytesPerRow: width * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
                DispatchQueue.main.async {
                    completion(nil)
                }
                return
            }
            
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            
            guard let data = context.data else {
                DispatchQueue.main.async {
                    completion(nil)
                }
                return
            }
            
            let pointer = data.bindMemory(to: UInt32.self, capacity: totalPixels)
            
            var totalRed: UInt64 = 0
            var totalGreen: UInt64 = 0
            var totalBlue: UInt64 = 0
            
            for i in 0..<totalPixels {
                let color = pointer[i]
                totalRed += UInt64(color & 0xFF)
                totalGreen += UInt64((color >> 8) & 0xFF)
                totalBlue += UInt64((color >> 16) & 0xFF)
            }
            
            let averageRed = CGFloat(totalRed) / CGFloat(totalPixels) / 255.0
            let averageGreen = CGFloat(totalGreen) / CGFloat(totalPixels) / 255.0
            let averageBlue = CGFloat(totalBlue) / CGFloat(totalPixels) / 255.0
            
            let minBrightness: CGFloat = 0.5
            let isNearBlack = averageRed < 0.03 && averageGreen < 0.03 && averageBlue < 0.03
            
            var finalColor: NSColor
            
            if isNearBlack {
                // If it's near black, just return a gray color with the minimum brightness
                finalColor = NSColor(white: minBrightness, alpha: 1.0)
            } else {
                var color = NSColor(red: averageRed, green: averageGreen, blue: averageBlue, alpha: 1.0)
                
                var hue: CGFloat = 0
                var saturation: CGFloat = 0
                var brightness: CGFloat = 0
                var alpha: CGFloat = 0
                
                color.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
                
                if brightness < minBrightness {
                    // Increase brightness while maintaining hue and reducing saturation
                    let saturationScale = brightness / minBrightness
                    color = NSColor(hue: hue,
                                    saturation: saturation * saturationScale,
                                    brightness: minBrightness,
                                    alpha: alpha)
                }
                
                finalColor = color
            }
            
            DispatchQueue.main.async {
                completion(finalColor)
            }
        }
        
    }
    
    func prominentOpposingColors(completion: @escaping (NSColor, NSColor) -> Void) {
        let isLegacyMode = Defaults[.colorExtractionMode] == .legacy
        DispatchQueue.global(qos: .userInitiated).async {
            // Step 1: Downsample the image
            let targetSize = CGSize(width: 64, height: 64)
            guard let cgImage = self.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                DispatchQueue.main.async { completion(.gray, .gray) }
                return
            }
            
            let width = Int(targetSize.width)
            let height = Int(targetSize.height)
            let totalPixels = width * height
            
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            let bytesPerPixel = 4
            let bytesPerRow = bytesPerPixel * width
            let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
            
            guard let context = CGContext(data: nil,
                                          width: width,
                                          height: height,
                                          bitsPerComponent: 8,
                                          bytesPerRow: bytesPerRow,
                                          space: colorSpace,
                                          bitmapInfo: bitmapInfo) else {
                DispatchQueue.main.async { completion(.gray, .gray) }
                return
            }
            
            context.interpolationQuality = .low
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
            
            guard let data = context.data else {
                DispatchQueue.main.async { completion(.gray, .gray) }
                return
            }
            let pointer = data.bindMemory(to: UInt32.self, capacity: totalPixels)
            
            let isLegacy = isLegacyMode
            if isLegacy {
                var totalRed: UInt64 = 0
                var totalGreen: UInt64 = 0
                var totalBlue: UInt64 = 0
                
                for i in 0..<totalPixels {
                    let color = pointer[i]
                    totalRed += UInt64(color & 0xFF)
                    totalGreen += UInt64((color >> 8) & 0xFF)
                    totalBlue += UInt64((color >> 16) & 0xFF)
                }
                
                let averageRed = CGFloat(totalRed) / CGFloat(totalPixels) / 255.0
                let averageGreen = CGFloat(totalGreen) / CGFloat(totalPixels) / 255.0
                let averageBlue = CGFloat(totalBlue) / CGFloat(totalPixels) / 255.0
                
                let minBrightness: CGFloat = 0.5
                let isNearBlack = averageRed < 0.03 && averageGreen < 0.03 && averageBlue < 0.03
                
                var primaryColor: NSColor
                if isNearBlack {
                    primaryColor = NSColor(white: minBrightness, alpha: 1.0)
                } else {
                    var color = NSColor(red: averageRed, green: averageGreen, blue: averageBlue, alpha: 1.0)
                    var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
                    color.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
                    
                    if brightness < minBrightness {
                        let saturationScale = brightness / minBrightness
                        color = NSColor(hue: hue,
                                        saturation: saturation * saturationScale,
                                        brightness: minBrightness,
                                        alpha: alpha)
                    }
                    primaryColor = color
                }
                
                var pHue: CGFloat = 0, pSat: CGFloat = 0, pBri: CGFloat = 0, pAlpha: CGFloat = 0
                primaryColor.getHue(&pHue, saturation: &pSat, brightness: &pBri, alpha: &pAlpha)
                
                let sHue = fmod(pHue + 0.5, 1.0)
                let secondaryColor = NSColor(hue: sHue, saturation: pSat, brightness: pBri, alpha: 1.0)
                
                DispatchQueue.main.async { completion(primaryColor, secondaryColor) }
                return
            }
            
            struct Bucket {
                var r: CGFloat = 0
                var g: CGFloat = 0
                var b: CGFloat = 0
                var weight: CGFloat = 0
            }
            
            let numBuckets = 16
            var buckets = Array(repeating: Bucket(), count: numBuckets)
            
            for i in 0..<totalPixels {
                let color = pointer[i]
                let rVal = color & 0xFF
                let gVal = (color >> 8) & 0xFF
                let bVal = (color >> 16) & 0xFF
                
                let r = CGFloat(rVal) / 255.0
                let g = CGFloat(gVal) / 255.0
                let b = CGFloat(bVal) / 255.0
                
                let nsColor = NSColor(red: r, green: g, blue: b, alpha: 1.0)
                var h: CGFloat = 0, s: CGFloat = 0, br: CGFloat = 0, a: CGFloat = 0
                nsColor.getHue(&h, saturation: &s, brightness: &br, alpha: &a)
                
                // Step 2: Ignore boring pixels
                if br < 0.10 || br > 0.95 || s < 0.20 {
                    continue
                }
                
                // Step 3: Weighted color extraction
                let weight = pow(s, 2.0) * br
                let bucketIndex = Int((h * CGFloat(numBuckets)).truncatingRemainder(dividingBy: CGFloat(numBuckets)))
                
                buckets[bucketIndex].r += r * weight
                buckets[bucketIndex].g += g * weight
                buckets[bucketIndex].b += b * weight
                buckets[bucketIndex].weight += weight
            }
            
            // Find primary bucket
            var primaryIndex = 0
            var maxWeight: CGFloat = -1
            for i in 0..<numBuckets {
                if buckets[i].weight > maxWeight {
                    maxWeight = buckets[i].weight
                    primaryIndex = i
                }
            }
            
            var primaryColor = NSColor.gray
            var pHue: CGFloat = 0, pSat: CGFloat = 0, pBri: CGFloat = 0, pAlpha: CGFloat = 1
            
            if maxWeight > 0 {
                let pBucket = buckets[primaryIndex]
                let pR = pBucket.r / pBucket.weight
                let pG = pBucket.g / pBucket.weight
                let pB = pBucket.b / pBucket.weight
                let rawPrimary = NSColor(red: pR, green: pG, blue: pB, alpha: 1.0)
                
                rawPrimary.getHue(&pHue, saturation: &pSat, brightness: &pBri, alpha: &pAlpha)
                
                // Step 4: Improve primary color
                pSat = min(1.0, pSat * 1.20)
                pBri = min(1.0, pBri * 1.10)
                
                primaryColor = NSColor(hue: pHue, saturation: pSat, brightness: pBri, alpha: 1.0)
            }
            
            // Step 5: Better secondary color
            var secondaryIndex = -1
            var bestScore: CGFloat = -1
            
            for i in 0..<numBuckets {
                if i == primaryIndex { continue }
                if buckets[i].weight <= 0 { continue }
                
                let hueDiff = abs(CGFloat(i - primaryIndex)) / CGFloat(numBuckets)
                let wrappedDiff = min(hueDiff, 1.0 - hueDiff) // 0.0 to 0.5
                let degreesDiff = wrappedDiff * 360.0
                
                // Acceptable distance: ~60 to 180 degrees
                if degreesDiff >= 60.0 {
                    let score = buckets[i].weight
                    if score > bestScore {
                        bestScore = score
                        secondaryIndex = i
                    }
                }
            }
            
            var secondaryColor = NSColor.gray
            
            if secondaryIndex != -1 && bestScore > 0 {
                let sBucket = buckets[secondaryIndex]
                let sR = sBucket.r / sBucket.weight
                let sG = sBucket.g / sBucket.weight
                let sB = sBucket.b / sBucket.weight
                
                let rawSecondary = NSColor(red: sR, green: sG, blue: sB, alpha: 1.0)
                var sHue: CGFloat = 0, sSat: CGFloat = 0, sBri: CGFloat = 0, sAlpha: CGFloat = 1
                rawSecondary.getHue(&sHue, saturation: &sSat, brightness: &sBri, alpha: &sAlpha)
                
                sSat = min(1.0, sSat * 1.20)
                sBri = min(1.0, sBri * 1.10)
                secondaryColor = NSColor(hue: sHue, saturation: sSat, brightness: sBri, alpha: 1.0)
            } else {
                // Fallback to complementary if no other bucket is found.
                // If no primary bucket was found either (maxWeight <= 0),
                // keep both colors gray instead of deriving a black color.
                if maxWeight > 0 {
                    let sHue = fmod(pHue + 0.5, 1.0)
                    secondaryColor = NSColor(hue: sHue, saturation: pSat, brightness: pBri, alpha: 1.0)
                }
            }
            
            DispatchQueue.main.async {
                completion(primaryColor, secondaryColor)
            }
        }
    }
    
    func getBrightness() -> CGFloat {
        guard let cgImage = self.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return 0
        }
        
        let inputImage = CIImage(cgImage: cgImage)
        
        let filter = CIFilter.areaAverage()
        filter.inputImage = inputImage
        filter.extent = inputImage.extent
        
        guard let outputImage = filter.outputImage else {
            return 0
        }
        
        let context = CIContext(options: nil)
        
        var bitmap = [UInt8](repeating: 0, count: 4)
        context.render(outputImage,
                       toBitmap: &bitmap,
                       rowBytes: 4,
                       bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                       format: .RGBA8,
                       colorSpace: CGColorSpaceCreateDeviceRGB())
        
        let brightness = (0.2126 * CGFloat(bitmap[0]) + 0.7152 * CGFloat(bitmap[1]) + 0.0722 * CGFloat(bitmap[2])) / 255.0
        
        return brightness
    }
}

extension Color {
    func ensureMinimumBrightness(factor: CGFloat) -> Color {
        guard factor >= 0 && factor <= 1 else {
            return self // Return original color if factor is out of bounds
        }
        
        let nsColor = NSColor(self)
        
        // Convert to RGB color space
        guard let rgbColor = nsColor.usingColorSpace(.sRGB) else {
            return self // Return original color if conversion fails
        }
        
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        
        rgbColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        
        // Calculate perceived brightness using the formula: (0.299*R + 0.587*G + 0.114*B)
        let perceivedBrightness = (0.2126 * red + 0.7152 * green + 0.0722 * blue)
        
        let scale = factor / perceivedBrightness
        red = min(red * scale, 1.0)
        green = min(green * scale, 1.0)
        blue = min(blue * scale, 1.0)
        
        
        return Color(red: Double(red), green: Double(green), blue: Double(blue), opacity: Double(alpha))
    }
    
    /// Creates a top-down gradient using the current color and its complementary (opposing) color.
    func spectrogramGradient(secondary: Color? = nil) -> AnyShapeStyle {
        if Defaults[.colorExtractionMode] == .legacy {
            return AnyShapeStyle(self.gradient)
        }
        
        if let secondary = secondary {
            return AnyShapeStyle(LinearGradient(
                colors: [self, secondary],
                startPoint: .top,
                endPoint: .bottom
            ))
        }
        
        let nsColor = NSColor(self).usingColorSpace(.sRGB) ?? NSColor.black
        
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        
        nsColor.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        
        // Shift hue by 180 degrees (0.5 in 0-1 scale)
        let opposingHue = fmod(hue + 0.5, 1.0)
        let opposingColor = Color(hue: Double(opposingHue), saturation: Double(saturation), brightness: Double(brightness), opacity: Double(alpha))
        
        return AnyShapeStyle(LinearGradient(
            colors: [self, opposingColor],
            startPoint: .top,
            endPoint: .bottom
        ))
    }
}
