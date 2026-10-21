import SwiftUI
import FormaCore

struct InspectorView: View {
    @ObservedObject var model: WorkspaceModel
    private let columns = [GridItem(.adaptive(minimum: 76, maximum: 110), spacing: 9)]
    var body: some View {
        VStack(alignment: .leading, spacing: 23) {
            Picker("Action", selection: Binding(get: { model.operation }, set: { model.select($0) })) {
                ForEach(model.operations) { action in Text(title(action)).tag(action) }
            }.pickerStyle(.menu).font(.system(size: 13))
            if !model.formats.isEmpty {
                VStack(alignment: .leading, spacing: 11) {
                    Text("Convert to").font(.system(size: 15, weight: .semibold))
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 9) {
                        ForEach(model.formats, id: \.self) { format in formatTile(format) }
                    }
                }
            }
            settings
        }.disabled(model.isRunning).frame(maxWidth: .infinity, alignment: .leading)
    }
    private func title(_ action: FormaCore.Operation) -> String {
        switch action { case .image, .media, .text: return "Convert"; default: return action.title }
    }
    private func formatTile(_ format: String) -> some View {
        let selected = model.options.format == format
        return Button { model.setFormat(format) } label: {
            VStack(spacing: 9) {
                Image(systemName: selected ? "checkmark.circle.fill" : "doc").font(.system(size: 19, weight: .light))
                Text(format.uppercased()).font(.system(size: 12, weight: .semibold))
            }.frame(maxWidth: .infinity).frame(height: 73)
                .foregroundStyle(selected ? Color.accentColor : Color.primary)
                .background(selected ? Color.accentColor.opacity(0.1) : Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(selected ? Color.accentColor : Color.primary.opacity(0.1), lineWidth: selected ? 1.5 : 1))
        }.buttonStyle(.plain).accessibilityLabel("Convert to \(format.uppercased())").accessibilityAddTraits(selected ? .isSelected : [])
    }
    @ViewBuilder private var settings: some View {
        switch model.operation {
        case .image:
            if ["jpeg", "heic"].contains(model.options.format) { quality }
            VStack(spacing: 13) {
                Picker("Crop", selection: $model.options.crop) {
                    Text("Original").tag("Original"); Text("Square").tag("Square")
                    ForEach(["4:3", "16:9", "9:16", "3:2"], id: \.self) { Text($0).tag($0) }
                }
                Picker("Filter", selection: $model.options.filter) {
                    ForEach(["None", "Mono", "Sepia", "Noir", "Vivid", "Fade", "Instant", "Tonal", "Process", "Transfer"], id: \.self) { Text($0).tag($0) }
                }
            }
            DisclosureGroup("Resize & rotate") {
                VStack(spacing: 14) {
                    dimensions
                    Picker("Rotation", selection: $model.options.rotation) {
                        Text("None").tag(0); Text("90°").tag(90); Text("180°").tag(180); Text("270°").tag(270)
                    }
                    Toggle("Remove metadata", isOn: $model.options.stripMetadata).toggleStyle(.checkbox)
                }.padding(.top, 13)
            }
        case .pdfLock:
            SecureField("New password", text: $model.options.password).textFieldStyle(.roundedBorder)
        case .pdfUnlock:
            SecureField("Current password", text: $model.options.password).textFieldStyle(.roundedBorder)
        case .pdfSplit, .pdfText, .pdfImages:
            TextField("Pages: all, or 1-3, 5", text: $model.options.pages).textFieldStyle(.roundedBorder)
            if model.operation == .pdfImages {
                if model.options.format == "jpeg" { quality }
                DisclosureGroup("Image size") { dimension("Width (px)", value: $model.options.width).padding(.top, 10) }
            }
            pdfPassword
        case .pdfMerge: pdfPassword
        case .media:
            if ["mp4", "mov", "webm", "mp3", "m4a"].contains(model.options.format) { quality }
            DisclosureGroup("Trim & resize") {
                VStack(spacing: 14) {
                    HStack {
                        VStack(alignment: .leading, spacing: 6) { Text("Start (s)"); TextField("0", value: $model.options.startSeconds, format: .number).textFieldStyle(.roundedBorder) }
                        VStack(alignment: .leading, spacing: 6) { Text("End (s)"); TextField("0", value: $model.options.endSeconds, format: .number).textFieldStyle(.roundedBorder) }
                    }
                    if ["mp4", "mov", "webm", "gif"].contains(model.options.format) { dimensions }
                }.padding(.top, 12)
            }
            if ConversionEngine.ffmpegPath == nil {
                VStack(alignment: .leading, spacing: 9) {
                    Label("FFmpeg required", systemImage: "exclamationmark.circle").foregroundStyle(.orange)
                    Text("brew install ffmpeg").font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                }
            }
        case .copy, .move:
            TextField("Filename prefix (optional)", text: $model.options.prefix).textFieldStyle(.roundedBorder)
        case .archive, .text: EmptyView()
        }
    }
    private var pdfPassword: some View {
        DisclosureGroup("Password") { SecureField("Current password", text: $model.options.password).textFieldStyle(.roundedBorder).padding(.top, 10) }
    }
    private var quality: some View {
        VStack(spacing: 7) {
            HStack { Text("Quality"); Spacer(); Text("\(Int(model.options.quality * 100))%").monospacedDigit().foregroundStyle(.secondary) }
            Slider(value: $model.options.quality, in: 0.1...1)
        }.font(.system(size: 12))
    }
    private var dimensions: some View {
        HStack(spacing: 10) {
            dimension("Width (px)", value: $model.options.width)
            Text("×").foregroundStyle(.secondary)
            dimension("Height (px)", value: $model.options.height)
        }
    }
    private func dimension(_ title: String, value: Binding<Int>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 11)).foregroundStyle(.secondary)
            TextField("Original", value: value, format: .number.grouping(.never)).textFieldStyle(.roundedBorder).accessibilityLabel(title).help("0 keeps the original dimension")
        }
    }
}
