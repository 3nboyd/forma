import Foundation
import Testing
import FormaCore
@testable import FormaApp

@MainActor
struct WorkspaceModelTests {
    private func fixture() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("forma-workspace-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    @Test func incomingFileChoosesConversionAndDestination() throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let image = root.appendingPathComponent("photo.png")
        try Data().write(to: image)
        let model = WorkspaceModel()
        model.add([image, image])
        #expect(model.files == [image])
        #expect(model.operation == .image)
        #expect(model.options.format == "jpeg")
        #expect(model.outputDirectory.standardizedFileURL == root.standardizedFileURL)
        #expect(model.browserDirectory.standardizedFileURL == root.standardizedFileURL)
        model.importFiles()
        #expect(model.browserVisible)
        #expect(model.files == [image])
        #expect(model.canRun)
    }

    @Test func mixedFilesStayAvailableWithCompatibleOptions() throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let image = root.appendingPathComponent("photo.png"), pdf = root.appendingPathComponent("pages.pdf")
        try Data().write(to: image); try Data().write(to: pdf)
        let model = WorkspaceModel()
        model.add([image, pdf])
        #expect(model.files.count == 2)
        #expect(!model.operations.contains(.image))
        model.selectGroup(.pdf)
        #expect(model.activeFiles == [pdf])
        #expect(model.operation == .pdfImages)
        #expect(model.formats == ["png", "jpeg"])
        model.selectGroup(.image)
        #expect(model.activeFiles == [image])
        #expect(model.operation == .image)
        model.selectGroup(nil)
        #expect(model.activeFiles.count == 2)
        #expect(model.operations == [.copy, .move, .archive])
        model.remove(pdf)
        #expect(model.operation == .image)
        #expect(model.formats.contains("jpeg"))
    }

    @Test func queueReorderingAndRemovalPreserveOtherFiles() throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let one = root.appendingPathComponent("one.pdf"), two = root.appendingPathComponent("two.pdf")
        try Data().write(to: one); try Data().write(to: two)
        let model = WorkspaceModel()
        model.add([one, two]); model.select(.pdfMerge)
        model.reorder(two, by: -1)
        #expect(model.activeFiles == [two, one])
        model.remove(one)
        #expect(model.files == [two])
        #expect(!model.operations.contains(.pdfMerge))
        #expect(model.operation == .pdfImages)
        model.clear()
        #expect(!model.canRun)
    }

    @Test func unsupportedFormatIsIgnoredAndSeparateBatchesAreDetected() throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let audio = root.appendingPathComponent("song.mp3"), video = root.appendingPathComponent("clip.mp4")
        try Data().write(to: audio); try Data().write(to: video)
        let model = WorkspaceModel()
        model.add([audio]); model.setFormat("mp4")
        #expect(model.options.format == "wav")
        #expect(!model.formats.contains("mp4"))
        model.clear(); model.add([video])
        #expect(model.operation == .media)
        #expect(model.formats.contains("mp4"))
        #expect(model.files == [video])
    }

    @Test func finderImportsDuringConversionAreRetained() async throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let one = root.appendingPathComponent("one.txt"), two = root.appendingPathComponent("two.txt")
        try Data("first".utf8).write(to: one); try Data("second".utf8).write(to: two)
        let model = WorkspaceModel()
        model.add([one]); model.select(.copy); model.run()
        #expect(model.isRunning)
        model.add([two, two])
        #expect(model.pendingImports == [two])
        #expect(model.files == [one])
        for _ in 0..<500 where model.isRunning { try await Task.sleep(for: .milliseconds(10)) }
        #expect(!model.isRunning)
        #expect(model.error == nil)
        #expect(model.results.count == 1)
        #expect(try Data(contentsOf: one) == Data("first".utf8))
        model.acceptPendingImports()
        #expect(model.pendingImports.isEmpty)
        #expect(model.files == [one, two])
    }

    @Test func moveRefreshesTheQueueToSavedLocations() async throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("move.txt")
        try Data("move me".utf8).write(to: file)
        let model = WorkspaceModel()
        model.add([file]); model.select(.move)
        model.outputDirectory = root.appendingPathComponent("destination")
        model.run()
        for _ in 0..<500 where model.isRunning { try await Task.sleep(for: .milliseconds(10)) }
        #expect(!model.isRunning)
        #expect(model.error == nil)
        #expect(model.results.count == 1)
        #expect(model.files == model.results)
        #expect(!FileManager.default.fileExists(atPath: file.path))
        #expect(model.files.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })
    }
}
