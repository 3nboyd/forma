import SwiftUI
import AppKit
import ImageIO
import CoreImage
import FormaCore

struct ImagePreview: View {
    let url: URL
    let options: ConversionOptions
    @State private var image: NSImage?
    @State private var size = ""
    @State private var loading = false
    private var key: String { "\(url.path)|\(options.crop)|\(options.filter)|\(options.rotation)|\(options.width)|\(options.height)" }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("LIVE PREVIEW").font(.system(size: 10, weight: .semibold)).tracking(1.4)
                Spacer()
                Text(size).font(.system(size: 10)).foregroundStyle(.secondary)
            }
            ZStack {
                RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor))
                if let image {
                    Image(nsImage: image).resizable().scaledToFit().padding(14).accessibilityLabel("Preview of \(url.lastPathComponent) with current image settings")
                } else if loading { ProgressView().controlSize(.small) }
                else { Label("Preview unavailable for this file", systemImage: "photo").font(.system(size: 11)).foregroundStyle(.secondary) }
            }.frame(height: 230).overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.primary.opacity(0.08)))
            Text("Preview shows shape, size, rotation, and filter. Export quality affects the saved file.").font(.system(size: 10)).foregroundStyle(.secondary)
        }
        .task(id: key) {
            loading = true
            let input = url, settings = options
            let output = await Task.detached(priority: .userInitiated) { Self.render(input, settings) }.value
            guard !Task.isCancelled else { return }
            image = output.map { NSImage(cgImage: $0.image, size: NSSize(width: $0.image.width, height: $0.image.height)) }
            size = output.map { "\($0.width) × \($0.height) px" } ?? ""
            loading = false
        }
    }
    private struct Rendered: @unchecked Sendable { let image: CGImage; let width: Int; let height: Int }
    nonisolated private static func render(_ url: URL, _ options: ConversionOptions) -> Rendered? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), let original = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] ?? [:]
        let orientation = (properties[kCGImagePropertyOrientation as String] as? NSNumber)?.int32Value ?? 1
        var image = CIImage(cgImage: original).oriented(forExifOrientation: orientation)
        if options.rotation != 0 { image = image.transformed(by: CGAffineTransform(rotationAngle: CGFloat(options.rotation) * .pi / 180)) }
        let ratios: [String: CGFloat] = ["Square": 1, "4:3": 4/3, "3:2": 3/2, "16:9": 16/9, "9:16": 9/16]
        if let ratio = ratios[options.crop] {
            let b = image.extent
            let w = min(b.width, b.height * ratio), h = min(b.height, b.width / ratio)
            image = image.cropped(to: CGRect(x: b.midX - w/2, y: b.midY - h/2, width: w, height: h))
        }
        let filters = ["Mono": "CIPhotoEffectMono", "Noir": "CIPhotoEffectNoir", "Sepia": "CISepiaTone", "Vivid": "CIPhotoEffectChrome", "Fade": "CIPhotoEffectFade", "Instant": "CIPhotoEffectInstant", "Tonal": "CIPhotoEffectTonal", "Process": "CIPhotoEffectProcess", "Transfer": "CIPhotoEffectTransfer"]
        if let name = filters[options.filter] { image = image.applyingFilter(name) }
        let bounds = image.extent
        let scale: CGFloat
        if options.width > 0 && options.height > 0 { scale = min(CGFloat(options.width)/bounds.width, CGFloat(options.height)/bounds.height) }
        else if options.width > 0 { scale = CGFloat(options.width)/bounds.width }
        else if options.height > 0 { scale = CGFloat(options.height)/bounds.height }
        else { scale = 1 }
        guard (1...16384).contains(bounds.width * scale), (1...16384).contains(bounds.height * scale) else { return nil }
        let width = Int(bounds.width * scale), height = Int(bounds.height * scale)
        let previewScale = min(1, 1000 / max(bounds.width, bounds.height))
        image = image.transformed(by: CGAffineTransform(translationX: -bounds.minX, y: -bounds.minY)).transformed(by: CGAffineTransform(scaleX: previewScale, y: previewScale))
        guard let result = CIContext().createCGImage(image, from: image.extent) else { return nil }
        return Rendered(image: result, width: width, height: height)
    }
}
