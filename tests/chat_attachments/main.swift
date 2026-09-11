import AppKit
import Foundation

let root = FileManager.default.temporaryDirectory.appendingPathComponent("atoll-chat-tests-" + UUID().uuidString)
try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: root) }
let output = root.appendingPathComponent("imports")
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 12, pixelsHigh: 8, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
for x in 0..<12 { for y in 0..<8 { bitmap.setColor(NSColor(calibratedRed: 0.1, green: 0.5, blue: 0.5, alpha: 1), atX: x, y: y) } }
let png = bitmap.representation(using: .png, properties: [:])!
let source = root.appendingPathComponent("test image.png")
try png.write(to: source)
let imported = try ChatAttachmentImport.prepare(file: source, directory: output)
assert(imported != source)
assert(imported.lastPathComponent == "test image.png")
try FileManager.default.removeItem(at: source)
let importedData = try Data(contentsOf: imported)
assert(importedData == png, "An imported image must survive removal of its drag source")
assert(ChatAttachmentImport.thumbnail(imported) != nil)
let tiff = bitmap.tiffRepresentation!
let normalized = try ChatAttachmentImport.prepare(data: tiff, name: "Screenshot.tiff", directory: output)
assert(normalized.pathExtension == "png")
let normalizedImage = try ImageAttachment(data: Data(contentsOf: normalized))
assert(normalizedImage.mimeType == "image/png")

func rejects(_ label: String, _ operation: () throws -> Void) {
    do { try operation(); fatalError("Accepted invalid input: \(label)") } catch {}
}
rejects("corrupt image") { _ = try ChatAttachmentImport.prepare(data: Data("bad image".utf8), directory: output) }
rejects("oversize image") { _ = try ChatAttachmentImport.prepare(data: Data(repeating: 0, count: ChatAttachmentImport.maximumBytes + 1), directory: output) }
rejects("folder") { _ = try ChatAttachmentImport.prepare(file: root, directory: output) }
rejects("remote URL") { _ = try ChatAttachmentImport.prepare(file: URL(string: "https://example.com/image.png")!, directory: output) }
let document = root.appendingPathComponent("notes.txt")
try Data("note".utf8).write(to: document)
let documentResult = try ChatAttachmentImport.prepare(file: document, directory: output)
assert(documentResult == document)
ChatAttachmentImport.removeOwnedFile(document)
assert(FileManager.default.fileExists(atPath: document.path), "Must never delete a user's source file")
print("Chat attachment tests passed: PNG import, source lifetime, thumbnail, TIFF normalization, corruption, size limit, folders, remote URLs, source-file protection")
