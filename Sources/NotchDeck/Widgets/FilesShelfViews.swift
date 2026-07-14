import AppKit
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

// inputs {model, onOpen}, does {compact Tray card: icon + count badge; click opens the takeover}, returns {View}
struct FilesCompactCardView: View {
    @ObservedObject var model: FilesShelfModel
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            VStack(spacing: 6) {
                Image(systemName: "tray.full")
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.55))
                    .overlay(alignment: .topTrailing) {
                        if !model.files.isEmpty {
                            Text("\(model.files.count)")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(3)
                                .background(Circle().fill(.blue))
                                .offset(x: 9, y: -8)
                        }
                    }
                Text("Tray")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// inputs {model, callbacks}, does {full-panel takeover: dashed Files Tray zone (left) + blue AirDrop zone (right); back via swipe-right or chevron}, returns {View}
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
        VStack(spacing: 6) {
            if model.files.isEmpty {
                Image(systemName: "tray.and.arrow.down")
                    .font(.title3)
                    .foregroundStyle(.white.opacity(trayTargeted ? 0.95 : 0.55))
                Text("Files Tray")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.55))
            } else {
                HStack(spacing: 4) {
                    ForEach(model.files.suffix(5), id: \.self) { url in
                        Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                            .resizable()
                            .frame(width: 26, height: 26)
                    }
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
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.title3)
                .foregroundStyle(.white.opacity(airTargeted ? 1 : 0.8))
            Text("AirDrop")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.8))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.blue.opacity(airTargeted ? 0.5 : 0.28))
        )
        .contentShape(RoundedRectangle(cornerRadius: 14))
        .onTapGesture { onAirDropShelf() }
        .onDrop(of: [.fileURL], isTargeted: $airTargeted) { providers in
            loadDroppedURLs(providers) { onAirDropped($0) }
            return true
        }
    }
}
