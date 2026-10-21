import SwiftUI
import AppKit
import FormaCore

@MainActor
final class WorkspaceModel: ObservableObject {
    @Published private(set) var files: [URL] = []
    @Published var group: FileKind? = nil
    @Published var operation: FormaCore.Operation = .image
    @Published var options = ConversionOptions()
    @Published var outputDirectory = FileManager.default.homeDirectoryForCurrentUser
    @Published private(set) var destinationChosen = false
    @Published private(set) var isRunning = false
    @Published private(set) var results: [URL] = []
    @Published private(set) var pendingImports: [URL] = []
    @Published var error: String?
    @Published var confirmMove = false
    @Published var isTargeted = false
    @Published var browserVisible = false
    @Published var browserDirectory = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first ?? FileManager.default.homeDirectoryForCurrentUser
    private var activePanel: NSOpenPanel?
    private var rememberedFormats: [FormaCore.Operation: String] = [:]

    var kinds: [FileKind] { Array(Set(files.map { FileCapabilities.kind(for: $0) })).sorted { $0.title < $1.title } }
    var activeFiles: [URL] { guard let group else { return files }; return files.filter { FileCapabilities.kind(for: $0) == group } }
    var operations: [FormaCore.Operation] { FileCapabilities.operations(for: activeFiles) }
    var formats: [String] { FileCapabilities.formats(for: operation, files: activeFiles) }
    var canRun: Bool { !activeFiles.isEmpty && !isRunning && operations.contains(operation) }
    var runTitle: String {
        switch operation {
        case .image, .media, .text, .pdfImages: return "Convert to \(options.format.uppercased())"
        default: return operation.title
        }
    }
    func selectGroup(_ value: FileKind?) {
        guard !isRunning else { return }
        group = value
        reconcile(forceDefault: true)
    }
    func select(_ value: FormaCore.Operation) {
        guard !isRunning, operations.contains(value) else { return }
        rememberedFormats[operation] = options.format
        operation = value
        options = ConversionOptions()
        chooseFormat()
        results = []; error = nil
    }
    func setFormat(_ format: String) {
        guard !isRunning, formats.contains(format) else { return }
        options.format = format; rememberedFormats[operation] = format
        results = []
    }
    private func chooseFormat() {
        let available = formats
        if let saved = rememberedFormats[operation], available.contains(saved) { options.format = saved }
        else { options.format = FileCapabilities.preferredFormat(for: operation, files: activeFiles) }
    }
    private func reconcile(forceDefault: Bool = false) {
        if let group, !kinds.contains(group) { self.group = nil }
        let available = operations
        if forceDefault || !available.contains(operation) {
            operation = FileCapabilities.defaultOperation(for: activeFiles) ?? .copy
            options = ConversionOptions()
        }
        if !formats.contains(options.format) || forceDefault { chooseFormat() }
    }
    func add(_ urls: [URL]) {
        let incoming = urls.filter(\.isFileURL).map(\.standardizedFileURL)
        if isRunning {
            for url in incoming where !files.contains(url) && !pendingImports.contains(url) { pendingImports.append(url) }
            return
        }
        guard !incoming.isEmpty else { return }
        browserVisible = false
        let wasEmpty = files.isEmpty
        for url in incoming where !files.contains(url) { files.append(url) }
        if wasEmpty, let first = files.first {
            browserDirectory = first.deletingLastPathComponent()
            if !destinationChosen { outputDirectory = browserDirectory }
        }
        reconcile(forceDefault: wasEmpty)
        results = []; error = nil
    }
    func remove(_ url: URL) {
        guard !isRunning else { return }
        let wasMixed = kinds.count > 1
        files.removeAll { $0 == url }; results = []
        reconcile(forceDefault: wasMixed && kinds.count == 1)
    }
    func reorder(_ url: URL, by offset: Int) {
        guard !isRunning, let index = files.firstIndex(of: url) else { return }
        let visible = activeFiles
        guard let visibleIndex = visible.firstIndex(of: url), visible.indices.contains(visibleIndex + offset),
              let target = files.firstIndex(of: visible[visibleIndex + offset]) else { return }
        files.swapAt(index, target); results = []
    }
    func clear() {
        guard !isRunning else { return }
        files = []; results = []; group = nil; error = nil
    }
    func importFiles() { browserVisible = true }
    func chooseOutput() {
        guard !isRunning, activePanel == nil else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.canCreateDirectories = true
        panel.prompt = "Choose"; panel.directoryURL = outputDirectory
        present(panel) { [weak self] response, urls in
            if response == .OK, let url = urls.first { self?.outputDirectory = url; self?.destinationChosen = true }
        }
    }
    private func present(_ panel: NSOpenPanel, completion: @escaping (NSApplication.ModalResponse, [URL]) -> Void) {
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow else { return }
        activePanel = panel
        panel.beginSheetModal(for: window) { [weak self] response in
            let urls = panel.urls
            self?.activePanel = nil
            DispatchQueue.main.async { completion(response, urls); window.makeKeyAndOrderFront(nil) }
        }
    }
    func requestRun() {
        guard canRun else { return }
        if operation == .move { confirmMove = true } else { run() }
    }
    func run() {
        guard canRun else { return }
        isRunning = true; error = nil; results = []
        let inputs = activeFiles, selected = operation, settings = options, destination = outputDirectory
        Task {
            do {
                let outputs = try await ConversionEngine.run(files: inputs, operation: selected, options: settings, outputDirectory: destination)
                if selected == .move {
                    let relocated = Dictionary(uniqueKeysWithValues: zip(inputs, outputs))
                    files = files.map { relocated[$0] ?? $0 }
                }
                results = outputs
            }
            catch { self.error = error.localizedDescription }
            isRunning = false
            // Keep completed results visible until the user accepts the queued imports.
        }
    }
    func acceptPendingImports() {
        guard !isRunning else { return }
        let urls = pendingImports; pendingImports = []; add(urls)
    }
    func reveal() { NSWorkspace.shared.activateFileViewerSelecting(results.isEmpty ? [outputDirectory] : results) }
}
