import SwiftUI
import FormaCore

struct InspectorView: View {
    @ObservedObject var model: WorkspaceModel
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack { Image(systemName: "slider.horizontal.3"); Text("Make it yours").font(.system(size: 14, weight: .semibold, design: .rounded)) }.padding(.top, 43).padding(.bottom, 25)
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    settings
                    Divider()
                    VStack(alignment: .leading, spacing: 10) {
                        sectionTitle("SAVE TO")
                        Button(action: model.chooseOutput) {
                            HStack(alignment: .top, spacing: 9) {
                                Image(systemName: "folder").font(.system(size: 17))
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(model.outputDirectory.lastPathComponent).font(.system(size: 12, weight: .medium)).lineLimit(2)
                                    Text("Choose another folder").font(.system(size: 10)).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.down").font(.system(size: 9))
                            }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                        }.buttonStyle(.plain).background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10)).help(model.outputDirectory.path)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Label("A fresh copy, every time", systemImage: "leaf").font(.system(size: 11, weight: .medium))
                        Text(model.operation == .move ? "Moving relocates originals within one disk. Use Copy files for another disk. You'll confirm before moving." : "Exports have unique names. Existing files are never overwritten.").font(.system(size: 10)).foregroundStyle(.secondary).lineSpacing(4)
                    }.padding(13).background(.green.opacity(0.055), in: RoundedRectangle(cornerRadius: 10))
                }
            }.scrollIndicators(.hidden)
            Spacer(minLength: 20)
            Text("BUILT FOR FOCUS, NOT FRICTION.").font(.system(size: 8, weight: .medium)).tracking(1.25).foregroundStyle(.secondary).padding(.bottom, 23)
        }.padding(.horizontal, 21).background(.background.opacity(0.6)).disabled(model.isRunning)
    }
    @ViewBuilder private var settings: some View {
        switch model.operation {
        case .image:
            VStack(alignment: .leading, spacing: 15) {
                sectionTitle("OUTPUT FORMAT")
                Picker("Format", selection: $model.options.format) {
                    Text("PNG · lossless").tag("png")
                    Text("JPEG · compact").tag("jpeg")
                    Text("HEIC · efficient").tag("heic")
                    Text("TIFF · high fidelity").tag("tiff")
                    Text("BMP · bitmap").tag("bmp")
                }.labelsHidden()
                if model.options.format == "jpeg" || model.options.format == "heic" { quality }
            }
            VStack(alignment: .leading, spacing: 13) {
                sectionTitle("SIZE & SHAPE")
                HStack {
                    dimension("Width", value: $model.options.width)
                    Text("×").foregroundStyle(.secondary)
                    dimension("Height", value: $model.options.height)
                }
                Text("Pixels. Set one side to resize proportionally, or both to fit within a box. Use 0 to keep the original size.").font(.system(size: 10)).foregroundStyle(.secondary).lineSpacing(3)
                Picker("Crop", selection: $model.options.crop) {
                    Text("Original").tag("Original")
                    Text("Square · 1:1").tag("Square")
                    Text("Classic · 4:3").tag("4:3")
                    Text("Wide · 16:9").tag("16:9")
                    Text("Portrait · 9:16").tag("9:16")
                    Text("Photo · 3:2").tag("3:2")
                }.font(.system(size: 11))
                Text("Crops are centered.").font(.system(size: 10)).foregroundStyle(.secondary)
                Picker("Rotation", selection: $model.options.rotation) {
                    Text("None").tag(0); Text("90°").tag(90); Text("180°").tag(180); Text("270°").tag(270)
                }.font(.system(size: 11))
            }
            VStack(alignment: .leading, spacing: 13) {
                sectionTitle("FINISHING TOUCHES")
                Picker("Filter", selection: $model.options.filter) {
                    ForEach(["None", "Mono", "Sepia", "Noir", "Vivid", "Fade", "Instant", "Tonal", "Process", "Transfer"], id: \.self) { Text($0).tag($0) }
                }.font(.system(size: 11))
                Toggle("Remove metadata", isOn: $model.options.stripMetadata).font(.system(size: 11)).toggleStyle(.checkbox)
            }
        case .pdfLock:
            VStack(alignment: .leading, spacing: 12) {
                sectionTitle("PDF PASSWORD")
                SecureField("Choose a password", text: $model.options.password).textFieldStyle(.roundedBorder)
                Text("Use this password to open your exported PDF. Keep a copy somewhere safe.").font(.system(size: 10)).foregroundStyle(.secondary).lineSpacing(4)
            }
        case .pdfUnlock:
            VStack(alignment: .leading, spacing: 12) {
                sectionTitle("CURRENT PASSWORD")
                SecureField("Enter PDF password", text: $model.options.password).textFieldStyle(.roundedBorder)
                Text("Enter a password you know to create an unlocked copy.").font(.system(size: 10)).foregroundStyle(.secondary).lineSpacing(4)
            }
        case .pdfSplit, .pdfText, .pdfImages:
            VStack(alignment: .leading, spacing: 12) {
                sectionTitle("PAGE SELECTION")
                TextField("All pages", text: $model.options.pages).textFieldStyle(.roundedBorder)
                Text("Leave blank for all pages, or enter a range like 1-3, 5, 8.").font(.system(size: 10)).foregroundStyle(.secondary).lineSpacing(4)
                if model.operation == .pdfImages {
                    Picker("Format", selection: $model.options.format) {
                        Text("PNG").tag("png"); Text("JPEG").tag("jpeg")
                    }.font(.system(size: 11))
                    dimension("Image width in pixels (0 = automatic)", value: $model.options.width)
                    if model.options.format == "jpeg" { quality }
                }
                SecureField("PDF password, if needed", text: $model.options.password).textFieldStyle(.roundedBorder)
                if model.operation == .pdfSplit { Text("Each selected page becomes a separate PDF.").font(.system(size: 11)).foregroundStyle(.secondary) }
            }
        case .pdfMerge:
            VStack(alignment: .leading, spacing: 12) {
                sectionTitle("ONE DOCUMENT, IN ORDER")
                Text("Add two or more PDFs. Arrange the queue in reading order with the arrow controls.").font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(5)
                SecureField("PDF password, if needed", text: $model.options.password).textFieldStyle(.roundedBorder)
            }
        case .media:
            VStack(alignment: .leading, spacing: 14) {
                sectionTitle("OUTPUT FORMAT")
                Picker("Format", selection: $model.options.format) {
                    ForEach(["mp4", "mov", "webm", "mp3", "m4a", "wav", "flac", "ogg", "gif"], id: \.self) { Text($0.uppercased()).tag($0) }
                }.labelsHidden()
                if ["mp4", "mov", "webm", "mp3", "m4a"].contains(model.options.format) { quality }
                if ["mp4", "mov", "webm", "gif"].contains(model.options.format) {
                    HStack {
                        dimension("Width", value: $model.options.width)
                        Text("×").foregroundStyle(.secondary)
                        dimension("Height", value: $model.options.height)
                    }
                    Text("Pixels. Use 0 for automatic sizing. Set one side to keep proportions; two dimensions set the exact shape.").font(.system(size: 10)).foregroundStyle(.secondary).lineSpacing(3)
                }
            }
            VStack(alignment: .leading, spacing: 12) {
                sectionTitle("TRIM CLIP")
                HStack {
                    VStack(alignment: .leading) { Text("Start (seconds)").font(.system(size: 10)); TextField("0", value: $model.options.startSeconds, format: .number).textFieldStyle(.roundedBorder) }
                    VStack(alignment: .leading) { Text("End (seconds)").font(.system(size: 10)); TextField("0", value: $model.options.endSeconds, format: .number).textFieldStyle(.roundedBorder) }
                }
                Text("End at 0 to keep the rest of the file.").font(.system(size: 10)).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 10) {
                sectionTitle("POWERED BY FFMPEG")
                Text(ConversionEngine.ffmpegPath == nil ? "FFmpeg is needed for media conversion. Install with Homebrew, then reopen Forma." : "FFmpeg is available on this Mac.").font(.system(size: 10)).foregroundStyle(.secondary).lineSpacing(4)
                if ConversionEngine.ffmpegPath == nil { Text("brew install ffmpeg").font(.system(size: 10, design: .monospaced)).textSelection(.enabled) }
            }
        case .copy, .move:
            VStack(alignment: .leading, spacing: 12) {
                sectionTitle("NAME YOUR COLLECTION")
                TextField("Optional filename prefix", text: $model.options.prefix).textFieldStyle(.roundedBorder)
                Text("A prefix is added before each original filename. Leave blank to keep the names.").font(.system(size: 10)).foregroundStyle(.secondary).lineSpacing(4)
            }
        case .archive:
            VStack(alignment: .leading, spacing: 12) {
                sectionTitle("ZIP ARCHIVE")
                Text("Combine the queue into one ZIP file. Files and folders keep their names inside the archive.").font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(5)
            }
        case .text:
            VStack(alignment: .leading, spacing: 12) {
                sectionTitle("OUTPUT FORMAT")
                Picker("Format", selection: $model.options.format) {
                    Text("Plain text · UTF-8").tag("txt")
                    Text("Rich text · RTF").tag("rtf")
                    Text("HTML").tag("html")
                    Text("Word · DOCX").tag("docx")
                    Text("Word · DOC").tag("doc")
                    Text("OpenDocument · ODT").tag("odt")
                }.labelsHidden()
                Text("Input must be compatible with the selected output. Invalid documents produce a helpful error.").font(.system(size: 10)).foregroundStyle(.secondary).lineSpacing(4)
            }
        }
    }
    private var quality: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack { Text("Quality"); Spacer(); Text("\(Int(model.options.quality * 100))%").monospacedDigit() }.font(.system(size: 11))
            Slider(value: $model.options.quality, in: 0.1...1)
            HStack { Text("Smaller file"); Spacer(); Text("Higher quality") }.font(.system(size: 9)).foregroundStyle(.secondary)
        }
    }
    private func sectionTitle(_ title: String) -> some View { Text(title).font(.system(size: 9, weight: .semibold)).tracking(1.3).foregroundStyle(.secondary) }
    private func dimension(_ title: String, value: Binding<Int>) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: 10)).foregroundStyle(.secondary)
            TextField("0", value: value, format: .number).textFieldStyle(.roundedBorder).font(.system(size: 11)).accessibilityLabel("\(title) in pixels")
        }
    }
}
