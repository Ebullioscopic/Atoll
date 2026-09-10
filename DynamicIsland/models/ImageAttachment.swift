import Foundation

struct ImageAttachment: Sendable {
    let mimeType: String
    let base64: String
    init(data: Data) throws {
        guard data.count <= 16 * 1024 * 1024 else {
            throw NSError(domain: "ImageAttachment", code: 1, userInfo: [NSLocalizedDescriptionKey: String(localized: "Each image must be at most 16 MB.")])
        }
        let bytes = [UInt8](data.prefix(12))
        if bytes.starts(with: [137,80,78,71,13,10,26,10]) { mimeType = "image/png" }
        else if bytes.starts(with: [255,216,255]) { mimeType = "image/jpeg" }
        else if data.starts(with: Data("GIF87a".utf8)) || data.starts(with: Data("GIF89a".utf8)) { mimeType = "image/gif" }
        else if bytes.count >= 12 && Array(bytes[0..<4]) == Array("RIFF".utf8) && Array(bytes[8..<12]) == Array("WEBP".utf8) { mimeType = "image/webp" }
        else { throw NSError(domain: "ImageAttachment", code: 2, userInfo: [NSLocalizedDescriptionKey: String(localized: "Use PNG, JPEG, GIF or WebP images.")]) }
        base64 = data.base64EncodedString()
    }
    var openAIContent: [String: Any] {
        ["type": "image_url", "image_url": ["url": "data:\(mimeType);base64,\(base64)"]]
    }
}
