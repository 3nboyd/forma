import SwiftUI
import AppKit
import UniformTypeIdentifiers
import ImageIO
import FormaCore

@main
struct FormaLauncher {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = FormaApplicationDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
        withExtendedLifetime(delegate) { }
    }
}

@MainActor
final class FormaApplicationDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuItemValidation {
    let model = WorkspaceModel()
    private var workspace: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureMenus()
        showWorkspace()
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWorkspace()
        return true
    }
    func application(_ application: NSApplication, open urls: [URL]) {
        model.add(urls)
        showWorkspace()
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    @objc private func addFiles() { showWorkspace(); model.importFiles() }
    @objc private func runWorkflow() { model.requestRun() }
    @objc private func showAbout() { NSApp.orderFrontStandardAboutPanel(nil) }
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(runWorkflow) { return !model.files.isEmpty && !model.isRunning }
        if menuItem.action == #selector(addFiles) { return !model.isRunning }
        return true
    }
    private func configureMenus() {
        let main = NSMenu()
        func menu(_ title: String) -> NSMenu {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            let child = NSMenu(title: title); item.submenu = child; main.addItem(item); return child
        }
        let appMenu = menu("Forma")
        let about = appMenu.addItem(withTitle: "About Forma", action: #selector(showAbout), keyEquivalent: ""); about.target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide Forma", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "Quit Forma", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let file = menu("File")
        let add = file.addItem(withTitle: "Add Files…", action: #selector(addFiles), keyEquivalent: "o"); add.target = self
        let run = file.addItem(withTitle: "Run Workflow", action: #selector(runWorkflow), keyEquivalent: "\r"); run.target = self
        file.addItem(.separator())
        file.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        let edit = menu("Edit")
        for (title, action, key) in [("Undo", "undo:", "z"), ("Cut", "cut:", "x"), ("Copy", "copy:", "c"), ("Paste", "paste:", "v"), ("Select All", "selectAll:", "a")] {
            edit.addItem(withTitle: title, action: Selector(action), keyEquivalent: key)
        }
        let window = menu("Window")
        window.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        window.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        NSApp.windowsMenu = window
        NSApp.mainMenu = main
    }

    private func showWorkspace() {
        if workspace == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1300, height: 820),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                                  backing: .buffered, defer: false)
            window.title = "Forma"
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.isReleasedWhenClosed = false
            window.contentMinSize = NSSize(width: 1080, height: 720)
            window.contentView = NSHostingView(rootView: WorkspaceView(model: model).frame(minWidth: 1080, minHeight: 720))
            window.delegate = self
            window.center()
            workspace = window
        }
        workspace?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@MainActor
final class WorkspaceModel: ObservableObject {
    @Published var operation: FormaCore.Operation = .image
    @Published var files: [URL] = []
    @Published var options = ConversionOptions()
    @Published var outputDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Forma Exports", isDirectory: true)
    @Published var isRunning = false
    @Published var results: [URL] = []
    @Published var error: String?
    @Published var confirmMove = false
    @Published var isTargeted = false
    private var activePanel: NSOpenPanel?

    func select(_ operation: FormaCore.Operation) {
        guard !isRunning else { return }
        self.operation = operation
        options = ConversionOptions()
        switch operation {
        case .image: options.format = "png"
        case .media: options.format = "mp4"
        case .archive: options.format = "zip"
        case .text: options.format = "txt"
        default: break
        }
        results = []
        error = nil
    }
    func add(_ urls: [URL]) {
        guard !isRunning else { return }
        for url in urls where url.isFileURL && !files.contains(url) { files.append(url) }
        results = []
        error = nil
    }
    func importFiles() {
        guard !isRunning, activePanel == nil else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = operation == .copy || operation == .move || operation == .archive
        panel.allowsMultipleSelection = true
        panel.message = "Choose files for your \(operation.title.lowercased()) workflow."
        present(panel) { [weak self] response, urls in
            if response == .OK { self?.add(urls) }
        }
    }
    func chooseOutput() {
        guard !isRunning, activePanel == nil else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "Choose folder"
        panel.directoryURL = outputDirectory
        present(panel) { [weak self] response, urls in
            if response == .OK, let url = urls.first { self?.outputDirectory = url }
        }
    }
    private func present(_ panel: NSOpenPanel, completion: @escaping (NSApplication.ModalResponse, [URL]) -> Void) {
        guard activePanel == nil else { return }
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first(where: { $0.isVisible && !($0 is NSPanel) }) else {
            error = "Open a Forma workspace window before choosing files."
            return
        }
        activePanel = panel
        panel.beginSheetModal(for: window) { [weak self, weak window] response in
            guard let self else { return }
            let urls = self.activePanel?.urls ?? []
            self.activePanel = nil
            // Finish the sheet transition before mutating the workspace or restoring focus.
            DispatchQueue.main.async {
                completion(response, urls)
                window?.makeKeyAndOrderFront(nil)
            }
        }
    }
    func requestRun() {
        guard !files.isEmpty, !isRunning else { return }
        if operation == .move { confirmMove = true } else { run() }
    }
    func run() {
        guard !files.isEmpty, !isRunning else { return }
        isRunning = true
        error = nil
        results = []
        let inputs = files, selected = operation, settings = options, destination = outputDirectory
        Task {
            do {
                results = try await ConversionEngine.run(files: inputs, operation: selected, options: settings, outputDirectory: destination)
            } catch { self.error = error.localizedDescription }
            isRunning = false
        }
    }
    func reveal() { NSWorkspace.shared.activateFileViewerSelecting(results.isEmpty ? [outputDirectory] : results) }
}

private enum Palette {
    static let ink = adaptive(light: NSColor(red: 0.13, green: 0.19, blue: 0.18, alpha: 1), dark: .labelColor)
    static let muted = Color(nsColor: .secondaryLabelColor)
    static let paper = adaptive(light: NSColor(red: 0.97, green: 0.965, blue: 0.94, alpha: 1), dark: NSColor(red: 0.12, green: 0.15, blue: 0.14, alpha: 1))
    static let teal = adaptive(light: NSColor(red: 0.12, green: 0.40, blue: 0.35, alpha: 1), dark: NSColor(red: 0.42, green: 0.77, blue: 0.65, alpha: 1))
    static let line = Color(nsColor: .separatorColor)
    static func adaptive(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light })
    }
}

struct WorkspaceView: View {
    @ObservedObject var model: WorkspaceModel
    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 226)
            Divider()
            VStack(alignment: .leading, spacing: 0) {
                header
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        dropZone
                        if model.operation == .image, let first = model.files.first { ImagePreview(url: first, options: model.options) }
                        if !model.files.isEmpty { queue }
                        if let error = model.error { message(error, symbol: "exclamationmark.circle.fill", color: .red) }
                        if !model.results.isEmpty { success }
                        if model.files.isEmpty { introduction }
                    }.padding(30)
                }
                footer
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            InspectorView(model: model).frame(width: 276)
        }
        .background(Palette.paper)
        .foregroundStyle(Palette.ink)
        .tint(Palette.teal)
        .alert("Move the original files?", isPresented: $model.confirmMove) {
            Button("Cancel", role: .cancel) {}
            Button("Move Files", role: .destructive) { model.run() }
        } message: { Text("This moves your original files into the selected output folder. They will no longer be in their current locations. Moving works within one disk; use Copy files for another disk.") }
    }
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                Image(systemName: "square.stack.3d.up.fill").font(.system(size: 26)).foregroundStyle(Palette.teal)
                Text("forma").font(.system(size: 30, weight: .semibold, design: .rounded)).tracking(-1)
                Circle().fill(Color.orange).frame(width: 6, height: 6).offset(y: 7)
            }.padding(.top, 37).padding(.bottom, 9).padding(.horizontal, 23)
            Text("A little order. Every file.").font(.system(size: 11)).foregroundStyle(Palette.muted).padding(.horizontal, 23).padding(.bottom, 30)
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    toolGroup("CREATE & CONVERT", operations: [.image, .media, .text])
                    toolGroup("PDF WORKSHOP", operations: [.pdfMerge, .pdfSplit, .pdfLock, .pdfUnlock, .pdfText, .pdfImages])
                    toolGroup("ORGANIZE", operations: [.copy, .move, .archive])
                }.padding(.horizontal, 12)
            }
            VStack(alignment: .leading, spacing: 8) {
                Label("Made to stay on your Mac", systemImage: "lock.shield").font(.system(size: 11, weight: .medium))
                Text("Local files. Local processing.\nNo uploads. No subscriptions.").font(.system(size: 10)).foregroundStyle(Palette.muted).lineSpacing(3)
            }.padding(22)
        }.background(Color(nsColor: .controlBackgroundColor).opacity(0.48))
    }
    private func toolGroup(_ title: String, operations: [FormaCore.Operation]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 9, weight: .semibold)).tracking(1.5).foregroundStyle(Palette.muted).padding(.leading, 11).padding(.bottom, 5)
            ForEach(operations) { operation in
                Button { model.select(operation) } label: {
                    HStack(spacing: 11) {
                        Image(systemName: operation.symbol).font(.system(size: 14)).frame(width: 20)
                        Text(operation.title).font(.system(size: 12, weight: model.operation == operation ? .semibold : .regular))
                        Spacer()
                        if model.operation == operation { Circle().fill(Palette.teal).frame(width: 5, height: 5) }
                    }.padding(.horizontal, 11).padding(.vertical, 9)
                        .foregroundStyle(model.operation == operation ? Palette.teal : Palette.ink)
                        .background(model.operation == operation ? Palette.teal.opacity(0.09) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                }.buttonStyle(.plain).disabled(model.isRunning)
            }
        }
    }
    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                Text("YOUR LOCAL FILE WORKSHOP").font(.system(size: 9, weight: .semibold)).tracking(1.8).foregroundStyle(Palette.muted)
                Text(model.operation.title).font(.system(size: 29, weight: .medium, design: .rounded)).tracking(-0.7)
                Text(model.operation.detail).font(.system(size: 12)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Image(systemName: model.operation.symbol).font(.system(size: 26, weight: .light)).foregroundStyle(Palette.teal).frame(width: 58, height: 58).background(Color(nsColor: .controlBackgroundColor).opacity(0.7), in: RoundedRectangle(cornerRadius: 17))
        }.padding(.horizontal, 30).padding(.top, 37).padding(.bottom, 24)
    }
    private var dropZone: some View {
        VStack(spacing: 13) {
            Image(systemName: "arrow.down.document").font(.system(size: 30, weight: .light)).foregroundStyle(Palette.teal).frame(width: 62, height: 62).background(Palette.teal.opacity(0.07), in: RoundedRectangle(cornerRadius: 18))
            Text(model.files.isEmpty ? "A fresh start for your files" : "There's room for more").font(.system(size: 19, weight: .medium, design: .rounded))
            Text("Drop files here, or choose them from your Mac.").font(.system(size: 12)).foregroundStyle(Palette.muted)
            Button(action: model.importFiles) { Label("Choose files", systemImage: "plus").padding(.horizontal, 10).padding(.vertical, 4) }.buttonStyle(.borderedProminent).controlSize(.large)
            Text("⌘ O to browse  ·  Multiple files welcome").font(.system(size: 10)).foregroundStyle(Palette.muted)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 32)
        .background(model.isTargeted ? Palette.teal.opacity(0.08) : Color(nsColor: .controlBackgroundColor).opacity(0.55), in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Palette.teal.opacity(model.isTargeted ? 0.8 : 0.25), style: StrokeStyle(lineWidth: 1.3, dash: [6, 5])))
        .dropDestination(for: URL.self) { urls, _ in model.add(urls); return !urls.isEmpty } isTargeted: { model.isTargeted = $0 }
        .disabled(model.isRunning)
    }
    private var queue: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("READY TO GO").font(.system(size: 10, weight: .semibold)).tracking(1.4)
                Text("\(model.files.count)").font(.system(size: 10, weight: .semibold)).padding(.horizontal, 7).padding(.vertical, 3).background(Palette.teal.opacity(0.08), in: Capsule())
                Spacer()
                Button("Clear all") { model.files = []; model.results = []; model.error = nil }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Palette.muted).disabled(model.isRunning)
            }
            VStack(spacing: 0) {
                ForEach(Array(model.files.enumerated()), id: \.element) { index, url in
                    HStack(spacing: 12) {
                        FileThumbnail(url: url).frame(width: 38, height: 38)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(url.lastPathComponent).font(.system(size: 12, weight: .medium)).lineLimit(1).truncationMode(.middle)
                            Text(fileDescription(url)).font(.system(size: 10)).foregroundStyle(Palette.muted)
                        }
                        Spacer()
                        if model.operation == .pdfMerge {
                            Button { model.files.swapAt(index, index - 1) } label: { Image(systemName: "arrow.up") }.disabled(index == 0 || model.isRunning).help("Move earlier in merged PDF").accessibilityLabel("Move \(url.lastPathComponent) earlier")
                            Button { model.files.swapAt(index, index + 1) } label: { Image(systemName: "arrow.down") }.disabled(index == model.files.count - 1 || model.isRunning).help("Move later in merged PDF").accessibilityLabel("Move \(url.lastPathComponent) later")
                        }
                        Button { model.files.removeAll { $0 == url }; model.results = [] } label: { Image(systemName: "xmark").font(.system(size: 10)) }.buttonStyle(.plain).foregroundStyle(Palette.muted).disabled(model.isRunning).accessibilityLabel("Remove \(url.lastPathComponent)")
                    }.padding(14)
                    if index < model.files.count - 1 { Divider().padding(.leading, 60) }
                }
            }.background(Color(nsColor: .controlBackgroundColor).opacity(0.75), in: RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Palette.line.opacity(0.7)))
            if model.operation == .pdfMerge { Text("Files merge in the order shown. Use ↑ and ↓ to reorder.").font(.system(size: 10)).foregroundStyle(Palette.muted) }
        }
    }
    private var introduction: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "sparkle").foregroundStyle(Color.orange).font(.system(size: 18))
            VStack(alignment: .leading, spacing: 7) {
                Text("Small tools. Thoughtful possibilities.").font(.system(size: 13, weight: .medium))
                Text(supportDescription).font(.system(size: 11)).foregroundStyle(Palette.muted).lineSpacing(5)
                Text(model.operation == .move ? "Moving relocates originals on the same disk. Use Copy files for another disk." : "Your original files stay safe. New files go to your output folder.").font(.system(size: 10)).foregroundStyle(Palette.muted)
            }
        }.padding(.top, 4)
    }
    private var supportDescription: String {
        switch model.operation {
        case .image: return "Convert common images, adjust size, crop to a new shape, add a filter, and choose the right balance of quality and file size."
        case .media: return "Convert audio and video with FFmpeg. Choose an output format, set quality, or trim a clip. Install FFmpeg with Homebrew: brew install ffmpeg."
        case .copy, .move: return "Gather files in one place. Add a filename prefix to keep a collection organized. Existing files are protected from overwriting."
        case .archive: return "Bundle your selected files and folders into a ZIP archive, ready to share or keep together."
        case .text: return "Convert TXT, RTF, HTML, Word, and OpenDocument files using the document tools built into macOS."
        default: return "Work with PDFs entirely on your Mac. Add your documents, choose your settings, and create a fresh export in seconds."
        }
    }
    private var success: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill").font(.title2).foregroundStyle(Palette.teal)
            VStack(alignment: .leading, spacing: 3) {
                Text("All done. Looking good.").font(.system(size: 13, weight: .semibold))
                Text("\(model.results.count) \(model.results.count == 1 ? "file" : "files") saved to \(model.outputDirectory.lastPathComponent)").font(.system(size: 11)).foregroundStyle(Palette.muted)
            }
            Spacer()
            Button("Show in Finder", action: model.reveal).controlSize(.small)
        }.padding(16).background(Palette.teal.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
    }
    private func message(_ text: String, symbol: String, color: Color) -> some View {
        Label(text, systemImage: symbol).font(.system(size: 12)).foregroundStyle(color).textSelection(.enabled).padding(16).frame(maxWidth: .infinity, alignment: .leading).background(color.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
    }
    private var footer: some View {
        HStack(spacing: 14) {
            if model.isRunning {
                ProgressView().controlSize(.small)
                Text("Working locally…").font(.system(size: 12)).foregroundStyle(Palette.muted)
            } else {
                Image(systemName: "checkmark.shield").foregroundStyle(Palette.teal)
                Text(model.files.isEmpty ? "Add files to get started" : "\(model.files.count) files ready").font(.system(size: 11)).foregroundStyle(Palette.muted)
            }
            Spacer()
            Button(action: model.requestRun) {
                HStack(spacing: 9) { Text(model.isRunning ? "Processing…" : "Run workflow"); Image(systemName: "arrow.right") }.font(.system(size: 12, weight: .semibold)).padding(.horizontal, 14).padding(.vertical, 8)
            }.buttonStyle(.borderedProminent).disabled(model.files.isEmpty || model.isRunning)
        }.padding(.horizontal, 30).padding(.vertical, 18).background(Color(nsColor: .controlBackgroundColor).opacity(0.65)).overlay(alignment: .top) { Divider() }
    }
    private func fileDescription(_ url: URL) -> String {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map { ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file) } ?? "Folder"
        return "\(url.pathExtension.isEmpty ? "FILE" : url.pathExtension.uppercased())  ·  \(size)"
    }
}

private struct FileThumbnail: View {
    let url: URL
    @State private var thumbnail: NSImage?
    var body: some View {
        Image(nsImage: thumbnail ?? NSWorkspace.shared.icon(forFile: url.path))
            .resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 5))
            .task(id: url) {
                guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                      let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 100, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary) else { return }
                thumbnail = NSImage(cgImage: image, size: NSSize(width: CGFloat(image.width), height: CGFloat(image.height)))
            }
    }
}
