import UIKit
import ImageIO
import CoreServices
import UniformTypeIdentifiers
import AVFoundation

/// Resizes and re-encodes a picked image before uploading it to S3. We prefer
/// HEIC because it produces ~50–70% smaller payloads than equivalent-quality
/// JPEG and is supported natively on iOS without extra dependencies. JPEG is
/// used as a fallback for older devices that lack the HEIC encoder.
enum UploadImageCompressor {
    /// Maximum pixel size for the longer image edge after downscaling. Photos
    /// captured with iPhones are typically ~4000 px wide; 1600 px keeps OCR
    /// quality while shrinking byte size by ~6×.
    static let maxLongEdge: CGFloat = 1600

    /// Lossy quality for the encoded image (0.0–1.0). 0.7 is the sweet spot
    /// where compression artifacts are imperceptible on photographic content
    /// while file sizes shrink substantially.
    static let quality: CGFloat = 0.7

    struct Encoded {
        let data: Data
        let contentType: String
    }

    /// Returns the compressed payload along with the matching MIME type. The
    /// image is first downscaled (maintaining aspect ratio), then encoded as
    /// HEIC; on systems without HEIC support, JPEG is produced instead.
    static func encodeForUpload(_ image: UIImage) -> Encoded? {
        let downscaled = downscale(image, maxLongEdge: maxLongEdge)
        if let heic = encodeHEIC(downscaled, quality: quality) {
            return Encoded(data: heic, contentType: "image/heic")
        }
        if let jpeg = downscaled.jpegData(compressionQuality: quality) {
            return Encoded(data: jpeg, contentType: "image/jpeg")
        }
        return nil
    }

    private static func downscale(_ image: UIImage, maxLongEdge: CGFloat) -> UIImage {
        let pixelSize = CGSize(
            width: image.size.width * image.scale,
            height: image.size.height * image.scale
        )
        let longest = max(pixelSize.width, pixelSize.height)
        guard longest > maxLongEdge else {
            return image
        }
        let ratio = maxLongEdge / longest
        let targetSize = CGSize(
            width: floor(pixelSize.width * ratio),
            height: floor(pixelSize.height * ratio)
        )
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }

    private static func encodeHEIC(_ image: UIImage, quality: CGFloat) -> Data? {
        guard let cgImage = image.cgImage else { return nil }
        let data = NSMutableData()
        let heicType: CFString
        if #available(iOS 14.0, *) {
            heicType = UTType.heic.identifier as CFString
        } else {
            heicType = "public.heic" as CFString
        }
        guard let destination = CGImageDestinationCreateWithData(data, heicType, 1, nil) else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: quality
        ]
        CGImageDestinationAddImage(destination, cgImage, options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            return nil
        }
        return data as Data
    }
}
