import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum FileKind: String, CaseIterable, Identifiable, Sendable {
    case image, pdf, audio, video, document, folder, other

    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .image: "Image"
        case .pdf: "PDF"
        case .audio: "Audio"
        case .video: "Video"
        case .document: "Document"
        case .folder: "Folder"
        case .other: "File"
        }
    }
    public var symbol: String {
        switch self {
        case .image: "photo"
        case .pdf: "doc.richtext"
        case .audio: "waveform"
        case .video: "film"
        case .document: "doc.text"
        case .folder: "folder"
        case .other: "doc"
        }
    }
}

/// Options the local conversion engine can offer for the entire selection.
public enum FileCapabilities {
    private static let audioFormats = ["mp3", "m4a", "wav", "flac", "ogg"]
    private static let videoFormats = ["mp4", "mov", "webm", "gif"]
    private static let documentExtensions: Set<String> = ["txt", "rtf", "rtfd", "html", "htm", "doc", "docx", "odt", "wordml", "webarchive"]
    private static let imageTypes = Set(CGImageSourceCopyTypeIdentifiers() as! [String])

    public static func kind(for url: URL) -> FileKind {
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
            return .folder
        }
        let ext = url.pathExtension.lowercased()
        if ext == "pdf" { return .pdf }
        if documentExtensions.contains(ext) { return .document }
        if ["mp3", "m4a", "wav", "flac", "ogg", "oga", "opus", "aac", "aif", "aiff", "aifc", "wma", "caf", "ac3"].contains(ext) { return .audio }
        if ["mp4", "mov", "webm", "mkv", "avi", "m4v", "mpg", "mpeg", "mts", "m2ts", "wmv", "flv", "3gp"].contains(ext) { return .video }
        // SVG is an image UTType, but the image engine cannot rasterize it.
        if ext == "svg" || ext == "svgz" { return .other }
        if let type = UTType(filenameExtension: ext) {
            if type.conforms(to: .audio) { return .audio }
            if type.conforms(to: .movie) { return .video }
            if type.conforms(to: .image), imageTypes.contains(type.identifier) { return .image }
        }
        // Sniff image headers for extensionless files without decoding full pixels.
        if let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
           CGImageSourceGetCount(source) > 0 { return .image }
        return .other
    }

    public static func operations(for files: [URL]) -> [Operation] {
        guard !files.isEmpty else { return [] }
        let kinds = Set(files.map { kind(for: $0) })
        var result: [Operation] = []
        if kinds == [.image] { result = [.image] }
        else if kinds == [.pdf] {
            result = [.pdfImages, .pdfText]
            if files.count > 1 { result.append(.pdfMerge) }
            result += [.pdfSplit, .pdfLock, .pdfUnlock]
        } else if kinds == [.document] { result = [.text] }
        else if kinds.isSubset(of: [.audio, .video]) { result = [.media] }
        return result + [.copy, .move, .archive]
    }

    public static func formats(for operation: Operation, files: [URL]) -> [String] {
        guard operations(for: files).contains(operation) else { return [] }
        switch operation {
        case .image: return ["png", "jpeg", "heic", "tiff", "bmp"]
        case .pdfImages: return ["png", "jpeg"]
        case .pdfText: return ["txt"]
        case .pdfMerge, .pdfSplit, .pdfLock, .pdfUnlock: return ["pdf"]
        case .text: return ["txt", "rtf", "html", "docx", "doc", "odt"]
        case .media:
            return files.allSatisfy { kind(for: $0) == .video } ? videoFormats + audioFormats : audioFormats
        case .archive: return ["zip"]
        case .copy, .move: return []
        }
    }

    public static func defaultOperation(for files: [URL]) -> Operation? {
        operations(for: files).first
    }

    public static func preferredFormat(for operation: Operation, files: [URL]) -> String {
        let available = formats(for: operation, files: files)
        guard !available.isEmpty else { return "" }
        let ext = files.first?.pathExtension.lowercased()
        switch operation {
        case .image: return ext == "png" ? "jpeg" : "png"
        case .media:
            if files.allSatisfy({ kind(for: $0) == .video }) { return "mp4" }
            return files.allSatisfy({ $0.pathExtension.lowercased() == "mp3" }) ? "wav" : "mp3"
        case .text: return ext == "txt" ? "rtf" : "txt"
        default: return available[0]
        }
    }
}
