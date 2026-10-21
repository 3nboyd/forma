import SwiftUI
import AppKit

/// Enumerates one directory at a time. Symbolic links are displayed, never traversed.
struct FileBrowser: View {
    @Binding var folder: URL
    let add: ([URL]) -> Void
    @State private var entries: [BrowserEntry] = []
    @State private var selection: Set<URL> = []
    @State private var error: String?
    @State private var loading = false
    @State private var pathText = ""
    private var locations: [(String, URL)] {
        let fm = FileManager.default
        return [("Home", fm.homeDirectoryForCurrentUser), ("Downloads", fm.urls(for: .downloadsDirectory, in: .userDomainMask)[0]), ("Documents", fm.urls(for: .documentDirectory, in: .userDomainMask)[0])]
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                ForEach(locations, id: \.0) { title, url in
                    Button(title) { folder = url }.buttonStyle(.borderless).foregroundStyle(folder == url ? Color.accentColor : .secondary)
                }
                Divider().frame(height: 15)
                Button { folder = folder.deletingLastPathComponent() } label: { Image(systemName: "arrow.up") }.disabled(folder.path == "/").help("Enclosing folder")
                Menu {
                    ForEach(ancestors, id: \.self) { url in Button(url.path) { folder = url } }
                } label: { Image(systemName: "folder") }
                .menuStyle(.borderlessButton).frame(width: 30).help("Enclosing folders")
                TextField("Folder path", text: $pathText)
                    .textFieldStyle(.roundedBorder).font(.system(size: 11))
                    .onSubmit { folder = URL(fileURLWithPath: (pathText as NSString).expandingTildeInPath, isDirectory: true).standardizedFileURL }
                    .accessibilityLabel("Folder path").help("Enter a folder path, including /Volumes for external disks")
                Spacer()
                Button("Add \(selection.isEmpty ? "Files" : String(selection.count))") { add(Array(selection).sorted { $0.path < $1.path }); selection = [] }
                    .buttonStyle(.borderedProminent).disabled(selection.isEmpty)
            }.font(.system(size: 11)).padding(.horizontal, 24).padding(.vertical, 11)
            Divider()
            ZStack {
                List(selection: $selection) {
                    ForEach(entries) { entry in
                        HStack(spacing: 9) {
                            Image(systemName: entry.symbol).foregroundStyle(entry.directory ? Color.accentColor : .secondary).frame(width: 18)
                            Text(entry.url.lastPathComponent).lineLimit(1)
                            Spacer()
                            if entry.directory {
                                Button { folder = entry.url } label: { Image(systemName: "chevron.right") }.buttonStyle(.borderless).accessibilityLabel("Open \(entry.url.lastPathComponent)")
                            } else {
                                Text(entry.url.pathExtension.uppercased()).font(.system(size: 10)).foregroundStyle(.secondary)
                            }
                        }.font(.system(size: 12)).tag(entry.url)
                            .contentShape(Rectangle())
                            .onTapGesture(count: 2) { if entry.directory { folder = entry.url } else { add([entry.url]) } }
                    }
                }.listStyle(.plain)
                if loading { ProgressView().controlSize(.small) }
                else if let error { Text(error).font(.system(size: 12)).foregroundStyle(.secondary).padding() }
                else if entries.isEmpty { Text("Empty folder").font(.system(size: 12)).foregroundStyle(.secondary) }
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .task(id: folder) {
            selection = []; error = nil; loading = true; entries = []
            pathText = folder.path
            let requested = folder
            let result = await Task.detached(priority: .userInitiated) { Self.read(requested) }.value
            guard !Task.isCancelled, requested == folder else { return }
            switch result { case .success(let list): entries = list; case .failure(let problem): error = problem.localizedDescription }
            loading = false
        }
    }
    private var ancestors: [URL] {
        var result = [folder], current = folder
        while current.path != "/" { current = current.deletingLastPathComponent(); result.append(current) }
        return result
    }
    nonisolated private static func read(_ folder: URL) -> Result<[BrowserEntry], Error> {
        Result {
            let folderValues = try folder.resourceValues(forKeys: [.isSymbolicLinkKey])
            guard folderValues.isSymbolicLink != true else { throw CocoaError(.fileReadUnsupportedScheme) }
            return try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isPackageKey], options: [.skipsHiddenFiles]).map { url in
                let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isPackageKey])
                return BrowserEntry(url: url, directory: values.isDirectory == true && values.isSymbolicLink != true && values.isPackage != true, symbolicLink: values.isSymbolicLink == true)
            }.sorted { a, b in
                if a.directory != b.directory { return a.directory }
                return a.url.lastPathComponent.localizedStandardCompare(b.url.lastPathComponent) == .orderedAscending
            }
        }
    }
}
private struct BrowserEntry: Identifiable, Sendable {
    let url: URL
    let directory: Bool
    let symbolicLink: Bool
    var id: URL { url }
    var symbol: String { symbolicLink ? "link" : directory ? "folder.fill" : "doc" }
}
