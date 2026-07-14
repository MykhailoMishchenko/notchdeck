import AppKit
import QuickLookThumbnailing
import SwiftUI
import UniformTypeIdentifiers

// inputs {providers, completion}, does {extracts file URLs from drop providers and delivers them on main}, returns {}
func loadDroppedURLs(_ providers: [NSItemProvider], completion: @escaping ([URL]) -> Void) {
    let group = DispatchGroup()
    var urls: [URL] = []
    let lock = NSLock()
    for provider in providers {
        group.enter()
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            defer { group.leave() }
            guard let data = item as? Data,
                  let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
            lock.lock()
            urls.append(url)
            lock.unlock()
        }
    }
    group.notify(queue: .main) { completion(urls) }
}

// inputs {model, callbacks}, does {full-panel takeover: dashed Files Tray grid (left) + blue AirDrop zone (right); back via swipe-right or chevron}, returns {View}
struct FilesTakeoverView: View {
    @ObservedObject var model: FilesShelfModel
    let onDropped: ([URL]) -> Void
    let onAirDropped: ([URL]) -> Void
    let onAirDropShelf: () -> Void
    let onClear: () -> Void
    let onBack: () -> Void

    @State private var trayTargeted = false
    @State private var airTargeted = false

    var body: some View {
        HStack(spacing: 10) {
            trayZone
            airDropZone
        }
        .overlay(alignment: .topLeading) {
            Button(action: onBack) {
                Image(systemName: "chevron.backward.circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.45))
            }
            .buttonStyle(.plain)
            .padding(2)
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 15)
                .onEnded { value in
                    if value.translation.width > 40 { onBack() }
                }
        )
    }

    private var trayZone: some View {
        Group {
            if model.files.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "tray.and.arrow.down")
                        .font(.title3)
                        .foregroundStyle(.white.opacity(trayTargeted ? 0.95 : 0.55))
                    Text("Files Tray")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.55))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 4) {
                    ScrollView(showsIndicators: false) {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 38), spacing: 6)], spacing: 6) {
                            ForEach(model.files, id: \.self) { url in
                                FileThumbView(url: url)
                            }
                        }
                        .padding(.top, 10)
                        .padding(.horizontal, 10)
                    }
                    HStack(spacing: 8) {
                        Text("\(model.files.count) file\(model.files.count == 1 ? "" : "s")")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.55))
                        Button(action: onClear) {
                            Image(systemName: "trash")
                                .font(.system(size: 10))
                                .foregroundStyle(.white.opacity(0.45))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.bottom, 6)
                }
            }
        }
        .background(RoundedRectangle(cornerRadius: 14).fill(.white.opacity(trayTargeted ? 0.08 : 0.03)))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(
                    .white.opacity(trayTargeted ? 0.75 : 0.35),
                    style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])
                )
        )
        .onDrop(of: [.fileURL], isTargeted: $trayTargeted) { providers in
            loadDroppedURLs(providers) { onDropped($0) }
            return true
        }
    }

    private var airDropZone: some View {
        VStack(spacing: 6) {
            AirDropGlyph()
                .frame(width: 28, height: 28)
                .opacity(airTargeted ? 1 : 0.85)
            Text("AirDrop")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.85))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.blue.opacity(airTargeted ? 0.55 : 0.28))
        )
        .contentShape(Rectangle())
        .onDrop(of: [.fileURL], isTargeted: $airTargeted) { providers in
            Log.info("airdrop zone: drop received (\(providers.count) providers)")
            loadDroppedURLs(providers) { onAirDropped($0) }
            return true
        }
        .onTapGesture { onAirDropShelf() }
    }
}

// inputs {}, does {vector AirDrop glyph: concentric arcs with the bottom wedge cut, like Apple's icon}, returns {View}
struct AirDropGlyph: View {
    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let lineWidth = side * 0.075
            ZStack {
                ForEach(1..<5) { ring in
                    Circle()
                        .stroke(.white, lineWidth: lineWidth)
                        .frame(width: side * CGFloat(ring) / 4, height: side * CGFloat(ring) / 4)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .mask(BottomWedgeCutShape().fill(style: FillStyle(eoFill: true)))
        }
    }
}

// inputs {}, does {full rect minus a triangular wedge from center to bottom edge (even-odd fill)}, returns {Shape}
struct BottomWedgeCutShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addRect(rect)
        let center = CGPoint(x: rect.midX, y: rect.midY)
        path.move(to: center)
        path.addLine(to: CGPoint(x: rect.midX - rect.width * 0.30, y: rect.maxY + 1))
        path.addLine(to: CGPoint(x: rect.midX + rect.width * 0.30, y: rect.maxY + 1))
        path.closeSubpath()
        return path
    }
}

// inputs {url}, does {one tray item: QuickLook thumbnail for previewable files (images etc.), native macOS icon otherwise (folders/docs); soft individual hover zoom}, returns {View}
struct FileThumbView: View {
    let url: URL
    @State private var thumbnail: NSImage?
    @State private var hovered = false

    var body: some View {
        Group {
            if let thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable()
                    .scaledToFit()
            }
        }
        .frame(width: 38, height: 38)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .scaleEffect(hovered ? 1.15 : 1)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: hovered)
        .onHover { hovered = $0 }
        .onAppear { generateThumbnail() }
        .help(url.lastPathComponent)
    }

    // inputs {}, does {asks QuickLook for a real content thumbnail; keeps the macOS file icon when none exists}, returns {}
    private func generateThumbnail() {
        guard thumbnail == nil else { return }
        var isDirectory: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        guard !isDirectory.boolValue else { return }
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: CGSize(width: 76, height: 76),
            scale: 2,
            representationTypes: .thumbnail
        )
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { representation, _ in
            guard let cgImage = representation?.cgImage else { return }
            DispatchQueue.main.async {
                thumbnail = NSImage(cgImage: cgImage, size: .zero)
            }
        }
    }
}

