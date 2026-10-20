import Foundation
import AppKit
import CoreImage
import ImageIO
import UniformTypeIdentifiers
import PDFKit
import Darwin

public enum ConversionEngine {
    public static var ffmpegPath: String? {
        ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg", "/usr/bin/ffmpeg"].first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    public static func run(files: [URL], operation: Operation, options: ConversionOptions, outputDirectory: URL) async throws -> [URL] {
        try await Task.detached(priority: .userInitiated) {
            try execute(files: files, operation: operation, options: options, directory: outputDirectory)
        }.value
    }

    private static func execute(files: [URL], operation: Operation, options o: ConversionOptions, directory: URL) throws -> [URL] {
        let fm = FileManager.default
        guard !files.isEmpty else { throw ConversionError.invalid("Choose at least one file.") }
        guard o.quality.isFinite, (0...1).contains(o.quality), (0...16384).contains(o.width), (0...16384).contains(o.height), o.startSeconds.isFinite, o.endSeconds.isFinite, o.startSeconds >= 0, o.endSeconds >= 0, o.endSeconds == 0 || o.endSeconds > o.startSeconds else { throw ConversionError.invalid("Check quality, dimensions and trim times.") }
        guard !o.prefix.contains("/"), !o.prefix.contains(":"), !o.prefix.contains("\0") else { throw ConversionError.invalid("The filename prefix cannot contain path separators.") }
        for file in files {
            guard fm.fileExists(atPath: file.path) else { throw ConversionError.invalid("File no longer exists: \(file.lastPathComponent)") }
            var isDirectory: ObjCBool = false
            fm.fileExists(atPath: file.path, isDirectory: &isDirectory)
            if isDirectory.boolValue {
                let source = file.resolvingSymlinksInPath().standardizedFileURL.path
                let target = directory.resolvingSymlinksInPath().standardizedFileURL.path
                guard target != source, !target.hasPrefix(source + "/") else { throw ConversionError.invalid("Choose a destination outside the source folder.") }
                guard [.copy, .move, .archive].contains(operation) else { throw ConversionError.invalid("This operation requires files, not folders.") }
            }
        }
        if operation == .move {
            return try moveAtomically(files: files, prefix: o.prefix, directory: directory)
        }
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        // Work is staged on the destination volume and published only after conversion succeeds.
        let staging = directory.appendingPathComponent(".forma-" + UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: staging, withIntermediateDirectories: false)
        defer { try? fm.removeItem(at: staging) }
        var staged: [URL] = []
        func target(_ name: String, _ ext: String) -> URL {
            uniqueURL(in: staging, name: o.prefix + name, extension: ext)
        }
        switch operation {
        case .image:
            for file in files { let out = target(file.deletingPathExtension().lastPathComponent, normalized(o.format)); try image(file, to: out, options: o); staged.append(out) }
        case .pdfMerge:
            let merged = PDFDocument()
            for file in files {
                let doc = try pdf(file, password: o.password)
                for index in try pageIndices(o.pages, count: doc.pageCount) { guard let page = doc.page(at: index) else { continue }; merged.insert(page, at: merged.pageCount) }
            }
            let out = target("Merged", "pdf"); guard merged.write(to: out) else { throw ConversionError.failed("Could not write merged PDF.") }; staged.append(out)
        case .pdfSplit, .pdfLock, .pdfUnlock, .pdfText, .pdfImages:
            if operation == .pdfLock && o.password.isEmpty { throw ConversionError.invalid("Enter a password to protect the PDF.") }
            for file in files {
                let doc = try pdf(file, password: o.password)
                let indices = try pageIndices(o.pages, count: doc.pageCount)
                let name = file.deletingPathExtension().lastPathComponent
                if operation == .pdfLock || operation == .pdfUnlock {
                    // A fresh document prevents retaining source encryption settings.
                    let fresh = PDFDocument()
                    for index in indices { if let page = doc.page(at: index) { fresh.insert(page, at: fresh.pageCount) } }
                    let out = target(name + (operation == .pdfLock ? "-locked" : "-unlocked"), "pdf")
                    let settings: [PDFDocumentWriteOption: Any] = operation == .pdfLock ? [.userPasswordOption: o.password, .ownerPasswordOption: o.password] : [:]
                    guard fresh.write(to: out, withOptions: settings) else { throw ConversionError.failed("Could not write PDF.") }; staged.append(out)
                } else if operation == .pdfText {
                    let out = target(name, "txt")
                    let content = indices.compactMap { doc.page(at: $0)?.string }.joined(separator: "\n\n")
                    guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ConversionError.invalid("This PDF has no selectable text. Scanned pages require OCR.") }
                    try content.write(to: out, atomically: true, encoding: .utf8); staged.append(out)
                } else {
                    for index in indices {
                        guard let page = doc.page(at: index) else { continue }
                        if operation == .pdfSplit {
                            let single = PDFDocument(); single.insert(page, at: 0)
                            let out = target("\(name)-page-\(index + 1)", "pdf")
                            guard single.write(to: out) else { throw ConversionError.failed("Could not write PDF page.") }; staged.append(out)
                        } else {
                            let ext = normalized(o.format)
                            guard ["png", "jpg"].contains(ext) else { throw ConversionError.invalid("PDF page images support PNG and JPEG.") }
                            let bounds = page.bounds(for: .mediaBox)
                            guard bounds.width > 0, bounds.height > 0, bounds.width <= 16384, bounds.height <= 16384 else { throw ConversionError.invalid("PDF page dimensions are unsupported.") }
                            let width = o.width > 0 ? CGFloat(o.width) : min(bounds.width * 2, 4096)
                            let size = NSSize(width: width, height: width * bounds.height / bounds.width)
                            guard size.height <= 16384 else { throw ConversionError.invalid("Rendered PDF height exceeds 16384 pixels.") }
                            let thumbnail = page.thumbnail(of: size, for: .mediaBox)
                            guard let data = thumbnail.tiffRepresentation else { throw ConversionError.failed("Could not render PDF page.") }
                            let temp = staging.appendingPathComponent(UUID().uuidString + ".tiff"); try data.write(to: temp)
                            let out = target("\(name)-page-\(index + 1)", ext)
                            try image(temp, to: out, options: o); try fm.removeItem(at: temp); staged.append(out)
                        }
                    }
                }
            }
        case .move:
            preconditionFailure("Moves are handled before conversion staging.")
        case .copy:
            for file in files {
                let out = target(file.deletingPathExtension().lastPathComponent, file.pathExtension)
                try fm.copyItem(at: file, to: out); staged.append(out)
            }
        case .archive:
            let contents = staging.appendingPathComponent("contents", isDirectory: true)
            try fm.createDirectory(at: contents, withIntermediateDirectories: false)
            for file in files { try fm.copyItem(at: file, to: uniqueURL(in: contents, name: file.deletingPathExtension().lastPathComponent, extension: file.pathExtension)) }
            let out = target("Archive", "zip")
            try process("/usr/bin/ditto", ["-c", "-k", "--sequesterRsrc", "--keepParent", contents.path, out.path]); staged.append(out)
        case .text:
            let ext = o.format.lowercased()
            guard ["txt", "rtf", "html", "doc", "docx", "odt", "wordml", "webarchive"].contains(ext) else { throw ConversionError.invalid("Choose TXT, RTF, HTML, DOC, DOCX, ODT, WordML or WebArchive.") }
            for file in files {
                guard ["txt", "rtf", "rtfd", "html", "htm", "doc", "docx", "odt", "wordml", "webarchive"].contains(file.pathExtension.lowercased()) else { throw ConversionError.invalid("Unsupported document type: \(file.pathExtension)") }
                let out = target(file.deletingPathExtension().lastPathComponent, ext)
                try process("/usr/bin/textutil", ["-noload", "-nostore", "-convert", ext, "-output", out.path, file.path]); staged.append(out)
            }
        case .media:
            guard let ffmpeg = ffmpegPath else { throw ConversionError.invalid("Install FFmpeg locally to enable audio and video conversion (brew install ffmpeg).") }
            let ext = o.format.lowercased()
            guard ["mp4", "mov", "webm", "mp3", "m4a", "wav", "flac", "ogg", "gif"].contains(ext) else { throw ConversionError.invalid("Unsupported audio/video output format.") }
            for file in files {
                let out = target(file.deletingPathExtension().lastPathComponent, ext)
                var args = ["-nostdin", "-hide_banner", "-loglevel", "error", "-n", "-protocol_whitelist", "file,pipe"]
                if o.startSeconds > 0 { args += ["-ss", String(o.startSeconds)] }
                args += ["-i", file.path]
                if o.endSeconds > 0 { args += ["-t", String(o.endSeconds - o.startSeconds)] }
                if o.stripMetadata { args += ["-map_metadata", "-1"] }
                if ["mp4", "mov"].contains(ext) { args += ["-c:v", "libx264", "-crf", String(Int(18 + (1 - o.quality) * 20)), "-pix_fmt", "yuv420p", "-c:a", "aac", "-movflags", "+faststart"] }
                else if ext == "webm" { args += ["-c:v", "libvpx-vp9", "-crf", String(Int(15 + (1 - o.quality) * 35)), "-b:v", "0", "-c:a", "libopus"] }
                else if ext == "mp3" { args += ["-vn", "-c:a", "libmp3lame", "-q:a", String(Int((1 - o.quality) * 9))] }
                else if ext == "m4a" { args += ["-vn", "-c:a", "aac", "-b:a", "\(Int(64 + o.quality * 256))k"] }
                else if ["wav", "flac", "ogg"].contains(ext) { args += ["-vn"] }
                if ["mp4", "mov", "webm", "gif"].contains(ext), o.width > 0 || o.height > 0 { args += ["-vf", "scale=\(o.width > 0 ? o.width : -2):\(o.height > 0 ? o.height : -2)"] }
                args.append(out.path); try process(ffmpeg, args); staged.append(out)
            }
        }
        var published: [URL] = []
        do {
            for file in staged {
                guard fm.fileExists(atPath: file.path) else { throw ConversionError.failed("The converter produced no output.") }
                // moveItem refuses existing destinations, including a race with another writer.
                let out = uniqueURL(in: directory, name: file.deletingPathExtension().lastPathComponent, extension: file.pathExtension)
                try fm.moveItem(at: file, to: out); published.append(out)
            }
        } catch { for file in published { try? fm.removeItem(at: file) }; throw error }
        return published
    }

    /// A move changes directory entries atomically; it never snapshots bytes and deletes a newer source.
    /// Cross-volume moves intentionally require a separate, user-verifiable copy operation.
    private static func moveAtomically(files: [URL], prefix: String, directory: URL) throws -> [URL] {
        let fm = FileManager.default
        let sources = files.map { $0.standardizedFileURL }
        let canonical = sources.map { $0.resolvingSymlinksInPath().standardizedFileURL.path }
        for (index, path) in canonical.enumerated() {
            for other in canonical.dropFirst(index + 1) {
                guard path != other, !path.hasPrefix(other + "/"), !other.hasPrefix(path + "/") else {
                    throw ConversionError.invalid("Move each source only once. Choose either a folder or its contents, not both, including aliases to the same source.")
                }
            }
        }
        // Locate the destination volume before creating any directories or moving any source.
        var ancestor = directory.resolvingSymlinksInPath().standardizedFileURL
        var isDirectory: ObjCBool = false
        while !fm.fileExists(atPath: ancestor.path, isDirectory: &isDirectory) {
            let parent = ancestor.deletingLastPathComponent()
            guard parent.path != ancestor.path else { throw ConversionError.invalid("Could not locate the destination volume.") }
            ancestor = parent
        }
        guard isDirectory.boolValue else { throw ConversionError.invalid("The destination must be a folder.") }
        var destinationInfo = stat()
        guard lstat(ancestor.path, &destinationInfo) == 0 else { throw posixFailure("Could not inspect destination") }
        for source in sources {
            var sourceInfo = stat()
            guard lstat(source.path, &sourceInfo) == 0 else { throw posixFailure("Could not inspect \(source.path)") }
            guard sourceInfo.st_dev == destinationInfo.st_dev else {
                throw ConversionError.invalid("Move across disks is not supported; use Copy files and verify results.")
            }
        }
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        var moved: [(source: URL, destination: URL)] = []
        do {
            for source in sources {
                let name = prefix + source.deletingPathExtension().lastPathComponent
                let ext = source.pathExtension
                var index = 1
                while true {
                    let suffix = index == 1 ? "" : " (\(index))"
                    let destination = directory.appendingPathComponent(name + suffix + (ext.isEmpty ? "" : "." + ext))
                    if renamex_np(source.path, destination.path, UInt32(RENAME_EXCL)) == 0 {
                        moved.append((source, destination)); break
                    }
                    let code = errno
                    if code == EEXIST || code == ENOTEMPTY { index += 1; continue }
                    if code == EXDEV { throw ConversionError.invalid("Move across disks is not supported; use Copy files and verify results.") }
                    throw posixFailure("Could not move \(source.path)", code: code)
                }
            }
        } catch {
            var preserved: [String] = []
            for item in moved.reversed() {
                if renamex_np(item.destination.path, item.source.path, UInt32(RENAME_EXCL)) != 0 {
                    preserved.append(item.destination.path)
                }
            }
            if !preserved.isEmpty {
                throw ConversionError.failed("\(error.localizedDescription) Some files could not be restored because their original paths became unavailable. Your moved files remain intact at:\n" + preserved.joined(separator: "\n"))
            }
            throw error
        }
        return moved.map(\.destination)
    }

    private static func posixFailure(_ message: String, code: Int32 = errno) -> ConversionError {
        .failed(message + ": " + String(cString: strerror(code)))
    }

    public static func pageIndices(_ specification: String, count: Int) throws -> [Int] {
        guard count > 0 else { throw ConversionError.invalid("The PDF contains no pages.") }
        if specification.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return Array(0..<count) }
        var result: [Int] = []
        for part in specification.split(separator: ",", omittingEmptySubsequences: false) {
            let bounds = part.trimmingCharacters(in: .whitespaces).split(separator: "-", omittingEmptySubsequences: false)
            guard (1...2).contains(bounds.count), let start = Int(bounds[0]), start >= 1, start <= count else { throw ConversionError.invalid("Invalid page range. Use 1, 3-5 within the PDF's page count.") }
            let end: Int
            if bounds.count == 2 { guard let value = Int(bounds[1]), value >= start, value <= count else { throw ConversionError.invalid("Invalid page range.") }; end = value } else { end = start }
            for page in start...end where !result.contains(page - 1) { result.append(page - 1) }
        }
        return result
    }

    private static func normalized(_ format: String) -> String { switch format.lowercased() { case "jpeg": "jpg"; case "tif": "tiff"; default: format.lowercased() } }
    private static func uniqueURL(in directory: URL, name: String, extension ext: String) -> URL {
        var index = 1
        var candidate = directory.appendingPathComponent(name + (ext.isEmpty ? "" : "." + ext))
        while FileManager.default.fileExists(atPath: candidate.path) {
            index += 1; candidate = directory.appendingPathComponent("\(name) (\(index))" + (ext.isEmpty ? "" : "." + ext))
        }
        return candidate
    }
    private static func pdf(_ url: URL, password: String) throws -> PDFDocument {
        guard let doc = PDFDocument(url: url) else { throw ConversionError.invalid("Could not open PDF: \(url.lastPathComponent)") }
        if doc.isLocked && !doc.unlock(withPassword: password) { throw ConversionError.invalid("Incorrect or missing password for \(url.lastPathComponent).") }
        return doc
    }
    private static func process(_ executable: String, _ arguments: [String]) throws {
        let process = Process(); process.executableURL = URL(fileURLWithPath: executable); process.arguments = arguments
        // A file avoids pipe-buffer deadlocks for long ffmpeg error output.
        let log = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        _ = FileManager.default.createFile(atPath: log.path, contents: nil)
        defer { try? FileManager.default.removeItem(at: log) }
        let handle = try FileHandle(forWritingTo: log); defer { try? handle.close() }
        process.standardError = handle; process.standardOutput = FileHandle.nullDevice
        try process.run(); process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let message = (try? String(contentsOf: log, encoding: .utf8)) ?? ""
            throw ConversionError.failed("Conversion failed: " + String(message.suffix(2000)))
        }
    }

    private static func image(_ url: URL, to output: URL, options o: ConversionOptions) throws {
        let types: [String: String] = ["png": UTType.png.identifier, "jpg": UTType.jpeg.identifier, "heic": UTType.heic.identifier, "tiff": UTType.tiff.identifier, "bmp": UTType.bmp.identifier]
        guard let type = types[output.pathExtension.lowercased()], (CGImageDestinationCopyTypeIdentifiers() as! [String]).contains(type) else { throw ConversionError.invalid("Supported image outputs: PNG, JPEG, HEIC, TIFF and BMP (availability depends on macOS).") }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), let original = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw ConversionError.invalid("Could not decode image: \(url.lastPathComponent)") }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] ?? [:]
        let orientation = (properties[kCGImagePropertyOrientation as String] as? NSNumber)?.int32Value ?? 1
        var image = CIImage(cgImage: original).oriented(forExifOrientation: orientation)
        if o.rotation != 0 { image = image.transformed(by: CGAffineTransform(rotationAngle: CGFloat(o.rotation) * .pi / 180)) }
        let ratios: [String: CGFloat] = ["Square": 1, "1:1": 1, "4:3": 4/3, "3:2": 3/2, "16:9": 16/9, "9:16": 9/16]
        if o.crop != "Original" {
            guard let ratio = ratios[o.crop] else { throw ConversionError.invalid("Unsupported crop ratio.") }
            let bounds = image.extent
            let width = min(bounds.width, bounds.height * ratio), height = min(bounds.height, bounds.width / ratio)
            image = image.cropped(to: CGRect(x: bounds.midX - width / 2, y: bounds.midY - height / 2, width: width, height: height))
        }
        let filters = ["Mono": "CIPhotoEffectMono", "Noir": "CIPhotoEffectNoir", "Sepia": "CISepiaTone", "Vivid": "CIPhotoEffectChrome", "Fade": "CIPhotoEffectFade", "Instant": "CIPhotoEffectInstant", "Tonal": "CIPhotoEffectTonal", "Process": "CIPhotoEffectProcess", "Transfer": "CIPhotoEffectTransfer"]
        if o.filter != "None" { guard let name = filters[o.filter] else { throw ConversionError.invalid("Unsupported photo filter.") }; image = image.applyingFilter(name) }
        let bounds = image.extent
        let scale: CGFloat
        if o.width > 0 && o.height > 0 { scale = min(CGFloat(o.width) / bounds.width, CGFloat(o.height) / bounds.height) }
        else if o.width > 0 { scale = CGFloat(o.width) / bounds.width }
        else if o.height > 0 { scale = CGFloat(o.height) / bounds.height }
        else { scale = 1 }
        image = image.transformed(by: CGAffineTransform(translationX: -bounds.minX, y: -bounds.minY)).transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard image.extent.width <= 16384, image.extent.height <= 16384, image.extent.width >= 1, image.extent.height >= 1 else { throw ConversionError.invalid("Output dimensions must be between 1 and 16384 pixels.") }
        // JPEG cannot represent alpha; composite on white explicitly.
        if output.pathExtension == "jpg" { image = image.composited(over: CIImage(color: .white).cropped(to: image.extent)) }
        guard let cg = CIContext().createCGImage(image, from: image.extent), let destination = CGImageDestinationCreateWithURL(output as CFURL, type as CFString, 1, nil) else { throw ConversionError.failed("Could not create image output.") }
        var metadata: [String: Any] = o.stripMetadata ? [:] : properties
        metadata[kCGImagePropertyOrientation as String] = 1
        metadata[kCGImagePropertyPixelWidth as String] = cg.width
        metadata[kCGImagePropertyPixelHeight as String] = cg.height
        metadata[kCGImageDestinationLossyCompressionQuality as String] = o.quality
        CGImageDestinationAddImage(destination, cg, metadata as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw ConversionError.failed("Could not finish image conversion.") }
    }
}
