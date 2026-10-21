import SwiftUI
import AppKit
import ImageIO
import FormaCore

struct WorkspaceView: View {
    @ObservedObject var model: WorkspaceModel
    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if model.browserVisible {
                FileBrowser(folder: $model.browserDirectory) { model.add($0) }.frame(height: model.files.isEmpty ? 280 : 210)
                Divider()
            }
            if model.files.isEmpty { emptyState }
            else { editor }
            status
            if !model.files.isEmpty { Divider(); footer }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .tint(.accentColor)
        .overlay { if model.isTargeted { RoundedRectangle(cornerRadius: 12).strokeBorder(Color.accentColor, lineWidth: 3).padding(5).allowsHitTesting(false) } }
        .dropDestination(for: URL.self) { urls, _ in model.add(urls); return !urls.isEmpty } isTargeted: { model.isTargeted = $0 }
        .alert("Move original files?", isPresented: $model.confirmMove) {
            Button("Cancel", role: .cancel) {}
            Button("Move Files", role: .destructive) { model.run() }
        } message: { Text("The selected files will move to \(model.outputDirectory.path).") }
    }
    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "square.stack.3d.up.fill").foregroundStyle(Color.accentColor).font(.system(size: 21))
            Text("Forma").font(.system(size: 21, weight: .semibold, design: .rounded))
            Spacer()
            if !model.files.isEmpty {
                Button("Clear", action: model.clear).disabled(model.isRunning)
            }
            if !model.files.isEmpty || model.browserVisible {
                Button { withAnimation(.easeInOut(duration: 0.18)) { model.browserVisible.toggle() } } label: {
                    Label(model.browserVisible ? "Done" : "Add files", systemImage: model.browserVisible ? "xmark" : "plus")
                }.buttonStyle(.bordered)
            }
        }.buttonStyle(.borderless).padding(.horizontal, 25).padding(.top, 38).padding(.bottom, 18)
    }
    private var emptyState: some View {
        VStack(spacing: 22) {
            Spacer(minLength: 12)
            Image(systemName: "doc.badge.arrow.up").font(.system(size: 54, weight: .ultraLight)).foregroundStyle(Color.accentColor)
            Text("Drop files").font(.system(size: 31, weight: .medium, design: .rounded))
            if !model.browserVisible {
                Button("Browse") { withAnimation { model.browserVisible = true } }.buttonStyle(.borderedProminent).controlSize(.large)
            }
            Spacer(minLength: 12)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.35))
    }
    private var editor: some View {
        HStack(alignment: .top, spacing: 0) {
            fileTray.frame(minWidth: 300, idealWidth: 350, maxWidth: 390)
            Divider()
            ScrollView {
                InspectorView(model: model).padding(26)
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
    private var fileTray: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Text("\(model.activeFiles.count) \(model.activeFiles.count == 1 ? "file" : "files")").font(.system(size: 13, weight: .semibold))
                Spacer()
                if model.kinds.count > 1 { Text("\(model.files.count) total").font(.system(size: 11)).foregroundStyle(.secondary) }
            }
            if model.kinds.count > 1 { groups }
            if !model.browserVisible, model.operation == .image, let first = model.activeFiles.first {
                ImagePreview(url: first, options: model.options)
            } else if !model.browserVisible, let first = model.activeFiles.first {
                FileHero(url: first)
            }
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(model.activeFiles, id: \.self) { url in fileRow(url) }
                }
            }.frame(maxHeight: .infinity)
        }.padding(23).frame(maxHeight: .infinity, alignment: .top)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.35))
    }
    private var groups: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 5) { groupButtons }
            ScrollView(.horizontal) { HStack(spacing: 5) { groupButtons } }.scrollIndicators(.hidden)
        }
    }
    @ViewBuilder private var groupButtons: some View {
        groupButton("All", kind: nil)
        ForEach(model.kinds, id: \.self) { kind in groupButton(kind.title, kind: kind) }
    }
    private func groupButton(_ title: String, kind: FileKind?) -> some View {
        Button { model.selectGroup(kind) } label: {
            Text(title).font(.system(size: 11, weight: .medium)).padding(.horizontal, 10).padding(.vertical, 6)
                .background(model.group == kind ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.04), in: Capsule())
                .foregroundStyle(model.group == kind ? Color.accentColor : .primary)
        }.buttonStyle(.plain).disabled(model.isRunning)
    }
    private func fileRow(_ url: URL) -> some View {
        HStack(spacing: 9) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().scaledToFit().frame(width: 27, height: 30)
            Text(url.lastPathComponent).font(.system(size: 12)).lineLimit(1).truncationMode(.middle).help(url.path)
            Spacer(minLength: 2)
            if model.activeFiles.count > 1 {
                Menu {
                    Button("Move Earlier") { model.reorder(url, by: -1) }.disabled(url == model.activeFiles.first)
                    Button("Move Later") { model.reorder(url, by: 1) }.disabled(url == model.activeFiles.last)
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).frame(width: 18).fixedSize()
            }
            Button { model.remove(url) } label: { Image(systemName: "xmark").font(.system(size: 10)) }
                .buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel("Remove \(url.lastPathComponent)")
        }.padding(.horizontal, 9).padding(.vertical, 7).background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8)).disabled(model.isRunning)
    }
    @ViewBuilder private var status: some View {
        if let error = model.error {
            HStack(alignment: .top) {
                Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.red)
                Text(error).font(.system(size: 12)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                Button { model.error = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain)
            }.padding(16).background(Color.red.opacity(0.07))
        }
        if !model.results.isEmpty {
            HStack {
                Label("\(model.results.count) saved", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                Spacer()
                Button("Show in Finder", action: model.reveal)
                Button("New Files", action: model.clear)
            }.font(.system(size: 12)).padding(16).background(Color.green.opacity(0.07))
        }
        if !model.pendingImports.isEmpty {
            HStack {
                Text("\(model.pendingImports.count) new files waiting").font(.system(size: 12))
                Spacer()
                Button("Add Files", action: model.acceptPendingImports).disabled(model.isRunning)
            }.padding(14).background(Color.accentColor.opacity(0.07))
        }
    }
    private var footer: some View {
        HStack(spacing: 16) {
            Button(action: model.chooseOutput) {
                HStack(spacing: 9) {
                    Image(systemName: "folder").foregroundStyle(Color.accentColor)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Save to").font(.system(size: 10)).foregroundStyle(.secondary)
                        Text(model.outputDirectory.lastPathComponent).font(.system(size: 12, weight: .medium)).lineLimit(1).truncationMode(.middle)
                    }
                    Image(systemName: "chevron.down").font(.system(size: 9)).foregroundStyle(.secondary)
                }
            }.buttonStyle(.plain).help(model.outputDirectory.path).disabled(model.isRunning)
            Spacer()
            if model.isRunning { ProgressView().controlSize(.small); Text("Working…").font(.system(size: 12)).foregroundStyle(.secondary) }
            Button(action: model.requestRun) {
                HStack(spacing: 12) { Text(model.runTitle); Image(systemName: "arrow.right") }.font(.system(size: 13, weight: .semibold)).padding(.horizontal, 9).padding(.vertical, 7)
            }.buttonStyle(.borderedProminent).controlSize(.large).keyboardShortcut(.return, modifiers: .command).disabled(!model.canRun)
        }.padding(.horizontal, 25).padding(.vertical, 20)
    }
}

private struct FileHero: View {
    let url: URL
    var body: some View {
        VStack(spacing: 12) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().scaledToFit().frame(width: 76, height: 85)
            Text(url.pathExtension.uppercased()).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity).frame(height: 160)
    }
}
