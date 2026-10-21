import Foundation
import Testing
@testable import FormaCore

struct FileCapabilitiesTests {
    private func fixture(_ names: [String], run: ([URL]) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("forma-capabilities-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let urls = try names.map { name in
            let url = root.appendingPathComponent(name)
            try Data().write(to: url)
            return url
        }
        try run(urls)
    }

    @Test func imageOptionsAndReencoding() throws {
        try fixture(["photo.PNG", "photo.jpeg"]) { urls in
            #expect(FileCapabilities.kind(for: urls[0]) == .image)
            #expect(FileCapabilities.defaultOperation(for: urls) == .image)
            #expect(FileCapabilities.formats(for: .image, files: urls) == ["png", "jpeg", "heic", "tiff", "bmp"])
            #expect(FileCapabilities.preferredFormat(for: .image, files: [urls[0]]) == "jpeg")
            #expect(FileCapabilities.preferredFormat(for: .image, files: [urls[1]]) == "png")
        }
    }

    @Test func pdfMergeRequiresMultiplePDFs() throws {
        try fixture(["one.pdf", "two.PDF"]) { urls in
            #expect(FileCapabilities.defaultOperation(for: urls) == .pdfImages)
            #expect(!FileCapabilities.operations(for: [urls[0]]).contains(.pdfMerge))
            #expect(FileCapabilities.operations(for: urls) == [.pdfImages, .pdfText, .pdfMerge, .pdfSplit, .pdfLock, .pdfUnlock, .copy, .move, .archive])
            #expect(FileCapabilities.formats(for: .pdfImages, files: urls) == ["png", "jpeg"])
        }
    }

    @Test func mediaOutputsRespectAudioOnlyAndMixedSelections() throws {
        try fixture(["track.mp3", "track.flac", "movie.mov", "movie.mkv"]) { urls in
            let audio = [urls[0], urls[1]], video = [urls[2], urls[3]]
            #expect(FileCapabilities.kind(for: urls[1]) == .audio)
            #expect(FileCapabilities.kind(for: urls[3]) == .video)
            #expect(FileCapabilities.defaultOperation(for: urls) == .media)
            #expect(FileCapabilities.formats(for: .media, files: audio) == ["mp3", "m4a", "wav", "flac", "ogg"])
            #expect(FileCapabilities.formats(for: .media, files: urls) == ["mp3", "m4a", "wav", "flac", "ogg"])
            #expect(FileCapabilities.formats(for: .media, files: video) == ["mp4", "mov", "webm", "gif", "mp3", "m4a", "wav", "flac", "ogg"])
            #expect(FileCapabilities.preferredFormat(for: .media, files: [urls[0]]) == "wav")
        }
    }

    @Test func mixedUnknownAndUnsupportedFilesOnlyOfferStorageActions() throws {
        try fixture(["photo.png", "unknown.xyzforma", "vector.svg", "notes.md"]) { urls in
            #expect(FileCapabilities.kind(for: urls[2]) == .other)
            #expect(FileCapabilities.kind(for: urls[3]) == .other)
            #expect(FileCapabilities.operations(for: urls) == [.copy, .move, .archive])
            #expect(FileCapabilities.defaultOperation(for: urls) == .copy)
            #expect(FileCapabilities.formats(for: .image, files: urls).isEmpty)
            #expect(FileCapabilities.preferredFormat(for: .image, files: urls).isEmpty)
        }
    }

    @Test func documentsFoldersAndEmptySelections() throws {
        try fixture(["notes.txt", "report.docx"]) { urls in
            #expect(FileCapabilities.defaultOperation(for: urls) == .text)
            #expect(FileCapabilities.formats(for: .text, files: urls) == ["txt", "rtf", "html", "docx", "doc", "odt"])
            let folder = urls[0].deletingLastPathComponent()
            #expect(FileCapabilities.kind(for: folder) == .folder)
            #expect(FileCapabilities.operations(for: [folder]) == [.copy, .move, .archive])
        }
        #expect(FileCapabilities.operations(for: []).isEmpty)
        #expect(FileCapabilities.defaultOperation(for: []) == nil)
        #expect(FileCapabilities.formats(for: .media, files: []).isEmpty)
    }
}
