import Foundation

public enum Operation: String, CaseIterable, Identifiable, Sendable {
    case image, pdfMerge, pdfSplit, pdfLock, pdfUnlock, pdfText, pdfImages, media, copy, move, archive, text
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .image: "Images"
        case .pdfMerge: "Merge PDFs"
        case .pdfSplit: "Extract PDF pages"
        case .pdfLock: "Lock PDF"
        case .pdfUnlock: "Unlock PDF"
        case .pdfText: "PDF to text"
        case .pdfImages: "PDF to images"
        case .media: "Audio & video"
        case .copy: "Copy files"
        case .move: "Move files"
        case .archive: "Create ZIP"
        case .text: "Documents"
        }
    }
    public var symbol: String {
        switch self {
        case .image: "photo.on.rectangle"
        case .pdfMerge: "doc.on.doc"
        case .pdfSplit: "scissors"
        case .pdfLock: "lock.doc"
        case .pdfUnlock: "lock.open"
        case .pdfText: "doc.text"
        case .pdfImages: "photo.stack"
        case .media: "play.rectangle"
        case .copy: "doc.on.clipboard"
        case .move: "folder"
        case .archive: "archivebox"
        case .text: "text.document"
        }
    }
    public var detail: String {
        switch self {
        case .image: "Convert, resize, crop, rotate and apply photo filters."
        case .pdfMerge: "Combine PDFs in the order shown."
        case .pdfSplit: "Save selected pages as individual PDFs."
        case .pdfLock: "Protect PDFs with a password."
        case .pdfUnlock: "Remove protection using the existing password."
        case .pdfText: "Extract selectable text from PDFs. Scans require OCR elsewhere."
        case .pdfImages: "Render PDF pages as PNG or JPEG images."
        case .media: "Convert audio and video with a local FFmpeg installation."
        case .copy: "Copy files and folders to a destination."
        case .move: "Move files and folders to a destination."
        case .archive: "Bundle files and folders into a ZIP archive."
        case .text: "Convert text, RTF, HTML and Word documents with macOS textutil."
        }
    }
}

public struct ConversionOptions: Sendable {
    public var format: String
    public var quality: Double
    public var width: Int
    public var height: Int
    public var crop: String
    public var filter: String
    public var rotation: Int
    public var password: String
    public var pages: String
    public var prefix: String
    public var startSeconds: Double
    public var endSeconds: Double
    public var stripMetadata: Bool
    public init(format: String = "png", quality: Double = 0.85, width: Int = 0, height: Int = 0, crop: String = "Original", filter: String = "None", rotation: Int = 0, password: String = "", pages: String = "", prefix: String = "", startSeconds: Double = 0, endSeconds: Double = 0, stripMetadata: Bool = true) {
        self.format = format; self.quality = quality; self.width = width; self.height = height
        self.crop = crop; self.filter = filter; self.rotation = rotation; self.password = password
        self.pages = pages; self.prefix = prefix; self.startSeconds = startSeconds; self.endSeconds = endSeconds; self.stripMetadata = stripMetadata
    }
}

public enum ConversionError: LocalizedError {
    case invalid(String)
    case failed(String)
    public var errorDescription: String? {
        switch self { case .invalid(let message), .failed(let message): message }
    }
}
