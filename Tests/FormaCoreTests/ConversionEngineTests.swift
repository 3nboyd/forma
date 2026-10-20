import Testing
import Foundation
import CoreGraphics
import ImageIO
import PDFKit
import Darwin
@testable import FormaCore

struct ConversionEngineTests {
    func workspace() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("forma-test-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    func makeImage(at url: URL) throws {
        let context = CGContext(data: nil, width: 200, height: 100, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 0.8, green: 0.2, blue: 0.4, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 200, height: 100))
        let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, context.makeImage()!, nil)
        #expect(CGImageDestinationFinalize(dest))
    }
    func makePDF(at url: URL, pages: Int = 3) {
        var bounds = CGRect(x: 0, y: 0, width: 200, height: 100)
        let context = CGContext(url as CFURL, mediaBox: &bounds, nil)!
        for _ in 0..<pages { context.beginPDFPage(nil); context.setFillColor(CGColor(gray: 0.5, alpha: 1)); context.fill(bounds); context.endPDFPage() }
        context.closePDF()
    }
    @Test func pageRangesAreOrderedAndValidated() throws {
        #expect(try ConversionEngine.pageIndices("3,1-2,2", count: 4) == [2, 0, 1])
        #expect(try ConversionEngine.pageIndices("", count: 2) == [0, 1])
        for invalid in ["0", "4", "2-1", "1,", "x", "1-9"] {
            #expect(throws: ConversionError.self) { try ConversionEngine.pageIndices(invalid, count: 3) }
        }
    }
    @Test func imageCropResizeAndSourcePreservation() async throws {
        let root = try workspace(); defer { try? FileManager.default.removeItem(at: root) }
        let input = root.appendingPathComponent("photo.png"); try makeImage(at: input)
        let original = try Data(contentsOf: input)
        let result = try await ConversionEngine.run(files: [input], operation: .image, options: .init(format: "jpg", width: 40, crop: "Square", filter: "Mono", rotation: 90), outputDirectory: root)
        #expect(result.count == 1)
        let source = CGImageSourceCreateWithURL(result[0] as CFURL, nil)!
        let output = CGImageSourceCreateImageAtIndex(source, 0, nil)!
        #expect(output.width == 40); #expect(output.height == 40)
        #expect(try Data(contentsOf: input) == original)
    }
    @Test func copiesNeverOverwriteAndMovesKeepData() async throws {
        let root = try workspace(); defer { try? FileManager.default.removeItem(at: root) }
        let input = root.appendingPathComponent("note.txt"); try Data("hello".utf8).write(to: input)
        let copies = try await ConversionEngine.run(files: [input, input], operation: .copy, options: .init(), outputDirectory: root)
        #expect(Set(copies).count == 2); #expect(!copies.contains(input))
        for copy in copies { #expect(try String(contentsOf: copy, encoding: .utf8) == "hello") }
        let destination = root.appendingPathComponent("moved")
        let moved = try await ConversionEngine.run(files: [input], operation: .move, options: .init(), outputDirectory: destination)
        #expect(!FileManager.default.fileExists(atPath: input.path))
        #expect(try String(contentsOf: moved[0], encoding: .utf8) == "hello")
    }
    @Test func batchFailureLeavesNoPublishedOutputs() async throws {
        let root = try workspace(); defer { try? FileManager.default.removeItem(at: root) }
        let good = root.appendingPathComponent("good.png"); try makeImage(at: good)
        let bad = root.appendingPathComponent("bad.png"); try Data("not an image".utf8).write(to: bad)
        let output = root.appendingPathComponent("output")
        await #expect(throws: (any Error).self) { try await ConversionEngine.run(files: [good, bad], operation: .image, options: .init(), outputDirectory: output) }
        #expect(try FileManager.default.contentsOfDirectory(atPath: output.path).isEmpty)
    }
    @Test func pdfSplitMergeLockAndUnlock() async throws {
        let root = try workspace(); defer { try? FileManager.default.removeItem(at: root) }
        let input = root.appendingPathComponent("source.pdf"); makePDF(at: input)
        let split = try await ConversionEngine.run(files: [input], operation: .pdfSplit, options: .init(pages: "1,3"), outputDirectory: root)
        #expect(split.count == 2)
        #expect(split.allSatisfy { PDFDocument(url: $0)?.pageCount == 1 })
        let merged = try await ConversionEngine.run(files: split, operation: .pdfMerge, options: .init(), outputDirectory: root)
        #expect(PDFDocument(url: merged[0])?.pageCount == 2)
        let locked = try await ConversionEngine.run(files: [input], operation: .pdfLock, options: .init(password: "test-secret"), outputDirectory: root)
        #expect(PDFDocument(url: locked[0])?.isLocked == true)
        await #expect(throws: (any Error).self) { try await ConversionEngine.run(files: locked, operation: .pdfUnlock, options: .init(password: "wrong"), outputDirectory: root) }
        let unlocked = try await ConversionEngine.run(files: locked, operation: .pdfUnlock, options: .init(password: "test-secret"), outputDirectory: root)
        #expect(PDFDocument(url: unlocked[0])?.isLocked == false)
        #expect(PDFDocument(url: unlocked[0])?.pageCount == 3)
    }
    @Test func folderRecursionAndUnsafePrefixRejected() async throws {
        let root = try workspace(); defer { try? FileManager.default.removeItem(at: root) }
        await #expect(throws: (any Error).self) { try await ConversionEngine.run(files: [root], operation: .copy, options: .init(), outputDirectory: root.appendingPathComponent("inside")) }
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("inside").path))
        let input = root.appendingPathComponent("file.txt"); try Data().write(to: input)
        await #expect(throws: (any Error).self) { try await ConversionEngine.run(files: [input], operation: .copy, options: .init(prefix: "../escape"), outputDirectory: root) }
    }
    @Test func textAndZipUseLocalTools() async throws {
        let root = try workspace(); defer { try? FileManager.default.removeItem(at: root) }
        let input = root.appendingPathComponent("note.txt"); try "Hello local world".write(to: input, atomically: true, encoding: .utf8)
        let documents = try await ConversionEngine.run(files: [input], operation: .text, options: .init(format: "rtf"), outputDirectory: root)
        #expect(try String(contentsOf: documents[0], encoding: .utf8).contains("Hello local world"))
        let archive = try await ConversionEngine.run(files: [input], operation: .archive, options: .init(), outputDirectory: root)
        #expect(try Data(contentsOf: archive[0]).prefix(2) == Data([0x50, 0x4b]))
    }
    @Test func duplicateMovesAndOverlappingSourcesAreRejected() async throws {
        let root = try workspace(); defer { try? FileManager.default.removeItem(at: root) }
        let input = root.appendingPathComponent("file.txt"); try Data("safe".utf8).write(to: input)
        let output = root.appendingPathComponent("output")
        await #expect(throws: (any Error).self) { try await ConversionEngine.run(files: [input, input], operation: .move, options: .init(), outputDirectory: output) }
        #expect(FileManager.default.fileExists(atPath: input.path))
        #expect(!FileManager.default.fileExists(atPath: output.path))
        await #expect(throws: (any Error).self) { try await ConversionEngine.run(files: [root, input], operation: .move, options: .init(), outputDirectory: root.deletingLastPathComponent().appendingPathComponent(UUID().uuidString)) }
        #expect(FileManager.default.fileExists(atPath: input.path))
    }
    @Test func pdfRendersImagesAndRejectsScannedText() async throws {
        let root = try workspace(); defer { try? FileManager.default.removeItem(at: root) }
        let input = root.appendingPathComponent("scan.pdf"); makePDF(at: input)
        let images = try await ConversionEngine.run(files: [input], operation: .pdfImages, options: .init(width: 100, pages: "2"), outputDirectory: root)
        #expect(images.count == 1)
        let source = CGImageSourceCreateWithURL(images[0] as CFURL, nil)!
        let image = CGImageSourceCreateImageAtIndex(source, 0, nil)!
        #expect(image.width == 100); #expect(image.height == 50)
        await #expect(throws: (any Error).self) { try await ConversionEngine.run(files: [input], operation: .pdfText, options: .init(), outputDirectory: root) }
    }
    @Test func ffmpegTrimsAudioWhenAvailable() async throws {
        guard let ffmpeg = ConversionEngine.ffmpegPath else { return }
        let root = try workspace(); defer { try? FileManager.default.removeItem(at: root) }
        let input = root.appendingPathComponent("tone.wav")
        let process = Process(); process.executableURL = URL(fileURLWithPath: ffmpeg)
        process.arguments = ["-nostdin", "-loglevel", "error", "-f", "lavfi", "-i", "sine=frequency=440:duration=3", "-c:a", "pcm_s16le", input.path]
        try process.run(); process.waitUntilExit(); #expect(process.terminationStatus == 0)
        let output = try await ConversionEngine.run(files: [input], operation: .media, options: .init(format: "wav", startSeconds: 0.5, endSeconds: 1.5), outputDirectory: root)
        let byteCount = try Data(contentsOf: output[0]).count
        #expect((88000...90000).contains(byteCount))
        #expect(try Data(contentsOf: input).count > byteCount * 2)
    }

    @Test func atomicMovePreservesOpenFileWritesAndDirectories() async throws {
        let root = try workspace(); defer { try? FileManager.default.removeItem(at: root) }
        let input = root.appendingPathComponent("live.txt")
        try Data("before".utf8).write(to: input)
        let handle = try FileHandle(forWritingTo: input); defer { try? handle.close() }
        let folder = root.appendingPathComponent("folder")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        try Data("child".utf8).write(to: folder.appendingPathComponent("child.txt"))
        var before = stat(); #expect(lstat(input.path, &before) == 0)
        let outputs = try await ConversionEngine.run(files: [input, folder], operation: .move, options: .init(), outputDirectory: root.appendingPathComponent("destination"))
        try handle.seekToEnd(); try handle.write(contentsOf: Data("-after".utf8)); try handle.synchronize()
        #expect(try String(contentsOf: outputs[0], encoding: .utf8) == "before-after")
        var after = stat(); #expect(lstat(outputs[0].path, &after) == 0)
        #expect(before.st_ino == after.st_ino)
        #expect(try String(contentsOf: outputs[1].appendingPathComponent("child.txt"), encoding: .utf8) == "child")
        #expect(!FileManager.default.fileExists(atPath: folder.path))
    }
    @Test func atomicMoveAvoidsExistingFilesAndRejectsAliasDuplicates() async throws {
        let root = try workspace(); defer { try? FileManager.default.removeItem(at: root) }
        let input = root.appendingPathComponent("file.txt"); try Data("source".utf8).write(to: input)
        let alias = root.appendingPathComponent("alias.txt")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: input)
        let destination = root.appendingPathComponent("destination")
        await #expect(throws: (any Error).self) { try await ConversionEngine.run(files: [input, alias], operation: .move, options: .init(), outputDirectory: destination) }
        #expect(FileManager.default.fileExists(atPath: input.path))
        #expect(!FileManager.default.fileExists(atPath: destination.path))
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false)
        let existing = destination.appendingPathComponent("file.txt"); try Data("existing".utf8).write(to: existing)
        let outputs = try await ConversionEngine.run(files: [input], operation: .move, options: .init(), outputDirectory: destination)
        #expect(outputs[0].lastPathComponent == "file (2).txt")
        #expect(try String(contentsOf: existing, encoding: .utf8) == "existing")
        #expect(try String(contentsOf: outputs[0], encoding: .utf8) == "source")
    }
    @Test func crossVolumeMoveRejectsWholeBatchWhenFixtureExists() async throws {
        // Opt-in mounted-volume fixture allows CI or a developer to exercise EXDEV safely.
        guard let fixture = ProcessInfo.processInfo.environment["FORMA_TEST_OTHER_VOLUME"] else { return }
        let root = try workspace(); defer { try? FileManager.default.removeItem(at: root) }
        let input = root.appendingPathComponent("file.txt"); try Data("safe".utf8).write(to: input)
        let destination = URL(fileURLWithPath: fixture).appendingPathComponent("forma-test-" + UUID().uuidString)
        var sourceStat = stat(), targetStat = stat()
        #expect(lstat(root.path, &sourceStat) == 0)
        #expect(lstat(URL(fileURLWithPath: fixture).resolvingSymlinksInPath().path, &targetStat) == 0)
        guard sourceStat.st_dev != targetStat.st_dev else { Issue.record("FORMA_TEST_OTHER_VOLUME must name another filesystem"); return }
        await #expect(throws: (any Error).self) { try await ConversionEngine.run(files: [input], operation: .move, options: .init(), outputDirectory: destination) }
        #expect(FileManager.default.fileExists(atPath: input.path))
        #expect(!FileManager.default.fileExists(atPath: destination.path))
    }

    @Test func failedAtomicMoveRollsBackPreviousEntries() async throws {
        let root = try workspace(); defer { try? FileManager.default.removeItem(at: root) }
        let first = root.appendingPathComponent("short.txt")
        let second = root.appendingPathComponent(String(repeating: "a", count: 240) + ".txt")
        try Data("first".utf8).write(to: first); try Data("second".utf8).write(to: second)
        let destination = root.appendingPathComponent("destination")
        await #expect(throws: (any Error).self) { try await ConversionEngine.run(files: [first, second], operation: .move, options: .init(prefix: String(repeating: "p", count: 30)), outputDirectory: destination) }
        #expect(try String(contentsOf: first, encoding: .utf8) == "first")
        #expect(try String(contentsOf: second, encoding: .utf8) == "second")
        #expect(try FileManager.default.contentsOfDirectory(atPath: destination.path).isEmpty)
    }

}
