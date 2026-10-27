import ChatCore
import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Something attached to a message. Images go to the model as images; documents are
/// turned into text on-device, which works with every model.
struct Attachment: Identifiable, Equatable {
    let id: UUID
    var kind: AttachmentKind
    var filename: String
    var mimeType: String
    var data: Data
    var text: String

    static func == (a: Attachment, b: Attachment) -> Bool { a.id == b.id }

    var payload: AttachmentPayload {
        AttachmentPayload(
            kind: kind,
            filename: filename,
            mimeType: mimeType,
            data: kind == .image ? data : nil,
            text: kind == .document ? text : nil
        )
    }
}

enum AttachmentLoader {
    enum LoadError: LocalizedError {
        case unreadable(String)
        case unsupported(String)
        case scannedPDF(String)

        var errorDescription: String? {
            switch self {
            case .unreadable(let name): "Couldn't open \(name)."
            case .unsupported(let name): "DeepSeek can't read \(name). It takes images, PDFs and text-based files."
            case .scannedPDF(let name): "\(name) has no selectable text (it may be a scan). Try a screenshot of the page instead."
            }
        }
    }

    static let importableTypes: [UTType] = [.image, .pdf, .text, .sourceCode, .json, .commaSeparatedText, .rtf, .data]

    static func load(url: URL) throws -> Attachment {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        let name = url.lastPathComponent
        let type = (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType
            ?? UTType(filenameExtension: url.pathExtension)
            ?? .data

        if type.conforms(to: .image) {
            guard let data = try? Data(contentsOf: url) else { throw LoadError.unreadable(name) }
            return try image(data: data, filename: name)
        }

        if type.conforms(to: .pdf) {
            guard let pdf = PDFDocument(url: url) else { throw LoadError.unreadable(name) }
            let pages = (0..<pdf.pageCount).compactMap { pdf.page(at: $0)?.string }
            let text = pages.joined(separator: "\n\n")
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw LoadError.scannedPDF(name) }
            return document(text: text, filename: name, mimeType: "application/pdf")
        }

        if type.conforms(to: .rtf) {
            let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [.documentType: NSAttributedString.DocumentType.rtf]
            guard let attributed = try? NSAttributedString(url: url, options: options, documentAttributes: nil) else {
                throw LoadError.unreadable(name)
            }
            return document(text: attributed.string, filename: name, mimeType: "application/rtf")
        }

        guard let data = try? Data(contentsOf: url) else { throw LoadError.unreadable(name) }
        guard let text = decodeText(data) else { throw LoadError.unsupported(name) }
        return document(text: text, filename: name, mimeType: type.preferredMIMEType ?? "text/plain")
    }

    static func image(data: Data, filename: String) throws -> Attachment {
        guard let (out, mime) = ImageProcessing.prepareForUpload(data) else { throw LoadError.unreadable(filename) }
        return Attachment(id: UUID(), kind: .image, filename: filename, mimeType: mime, data: out, text: "")
    }

    private static func document(text: String, filename: String, mimeType: String) -> Attachment {
        let (body, _) = DocumentText.truncated(text)
        return Attachment(id: UUID(), kind: .document, filename: filename, mimeType: mimeType, data: Data(), text: body)
    }

    /// Text if the bytes look like text, nil for binary formats.
    private static func decodeText(_ data: Data) -> String? {
        if data.prefix(8192).contains(0) { return nil }
        return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
    }
}

enum ImageProcessing {
    /// DeepSeek accepts JPEG, PNG, GIF and WebP and caps image tokens anyway, so photos
    /// (often HEIC) are scaled to 2048px and re-encoded. PNG is kept when there's transparency.
    static func prepareForUpload(_ data: Data, maxPixel: Int = 2048) -> (Data, String)? {
        guard let image = downsample(data, maxPixel: maxPixel) else { return nil }
        let opaque: Bool = switch image.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast: true
        default: false
        }
        let type: UTType = opaque ? .jpeg : .png
        let out = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(out, type.identifier as CFString, 1, nil) else { return nil }
        let props: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: 0.85]
        CGImageDestinationAddImage(destination, image, props as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return (out as Data, opaque ? "image/jpeg" : "image/png")
    }

    static func downsample(_ data: Data, maxPixel: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}

/// Small decoded previews, so scrolling doesn't re-decode full images.
final class ThumbnailCache: @unchecked Sendable {
    static let shared = ThumbnailCache()

    private final class Box {
        let image: CGImage
        init(_ image: CGImage) { self.image = image }
    }

    private let cache = NSCache<NSUUID, Box>()

    func image(for attachment: Attachment, maxPixel: Int = 480) -> CGImage? {
        let key = attachment.id as NSUUID
        if let box = cache.object(forKey: key) { return box.image }
        guard let image = ImageProcessing.downsample(attachment.data, maxPixel: maxPixel) else { return nil }
        cache.setObject(Box(image), forKey: key)
        return image
    }
}
