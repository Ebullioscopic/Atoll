import Foundation
let png = Data([137,80,78,71,13,10,26,10])
let image = try ImageAttachment(data: png)
assert(image.mimeType == "image/png")
assert(image.base64 == png.base64EncodedString())
do {
    _ = try ImageAttachment(data: Data("not an image".utf8))
    fatalError("Non-image accepted")
} catch {}
print("Image attachment tests passed")
