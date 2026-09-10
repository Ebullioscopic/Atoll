import AppKit
import ImageIO
import UniformTypeIdentifiers

/// Own imported images so clipboard/drag sources can disappear without breaking a message.
enum ChatAttachmentImport {
    static let maximumImages = 8
    static let maximumBytes = 16 * 1024 * 1024
    static let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent(Bundle.main.bundleIdentifier ?? "Atoll", isDirectory: true)
        .appendingPathComponent("ChatAttachments", isDirectory: true)

    static func failure(_ message: String) -> NSError {
        NSError(domain: "ChatAttachmentImport", code: 1, userInfo: [NSLocalizedDescriptionKey: NSLocalizedString(message, comment: "Chat attachment error")])
    }

    static func prepare(file url: URL, directory: URL = directory) throws -> URL {
        guard url.isFileURL else { throw failure("Please drop a local file or paste an image.") }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true else { throw failure("Folders cannot be attached. Please choose files.") }
        let imageExtensions = ["png", "jpg", "jpeg", "gif", "webp", "heic", "heif", "bmp", "tif", "tiff"]
        let contentType = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType
        guard contentType?.conforms(to: .image) == true || imageExtensions.contains(url.pathExtension.lowercased()) else {
            guard FileManager.default.isReadableFile(atPath: url.path) else { throw failure("This file could not be read.") }
            return url
        }
        guard (values.fileSize ?? 0) <= maximumBytes else { throw failure("Each image must be at most 16 MB.") }
        return try prepare(data: Data(contentsOf: url), name: url.lastPathComponent, directory: directory)
    }

    static func prepare(data: Data, name: String = "Pasted image.png", directory: URL = directory) throws -> URL {
        guard data.count <= maximumBytes else { throw failure("Each image must be at most 16 MB.") }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, Double(width) * Double(height) <= 80_000_000 else {
            throw failure("This image cannot be read, or is too large. Please use an image under 80 megapixels.")
        }
        var output = data
        var filename = URL(fileURLWithPath: name).lastPathComponent
        // Preserve supported formats; normalize HEIC, TIFF and clipboard bitmaps to PNG.
        if (try? ImageAttachment(data: data)) == nil {
            guard let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil),
                  let png = NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:]) else {
                throw failure("This image could not be converted to PNG.")
            }
            output = png
            filename = URL(fileURLWithPath: filename).deletingPathExtension().lastPathComponent + ".png"
        }
        _ = try ImageAttachment(data: output)
        let folder = directory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let destination = folder.appendingPathComponent(filename)
        do { try output.write(to: destination, options: .atomic) }
        catch { try? FileManager.default.removeItem(at: folder); throw error }
        return destination
    }

    static func removeOwnedFile(_ url: URL) {
        // Never remove a source file selected by the user.
        guard url.deletingLastPathComponent().deletingLastPathComponent().standardizedFileURL == directory.standardizedFileURL else { return }
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }

    static func thumbnailData(_ url: URL) -> Data? {
        thumbnail(url)?.tiffRepresentation
    }

    static func thumbnail(_ url: URL, size: Int = 240) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: size,
                kCGImageSourceCreateThumbnailWithTransform: true
              ] as CFDictionary) else { return nil }
        return NSImage(cgImage: image, size: .zero)
    }
}
