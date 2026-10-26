import AVKit
import SwiftUI

/// Full-window viewer: arrow keys move between items, Esc closes.
struct ViewerView: View {
    @EnvironmentObject private var gallery: GalleryModel
    let items: [GalleryItem]
    @Binding var index: Int
    let close: () -> Void

    private var item: GalleryItem { items[index] }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            Group {
                if item.isVideo {
                    VideoPane(url: item.url, autoplay: true).id(item.id)
                } else {
                    PhotoPane(item: item).id(item.id)
                }
            }
            VStack {
                topBar
                Spacer()
            }
            // Invisible buttons give the viewer its keyboard shortcuts.
            Group {
                Button("Close", action: close).keyboardShortcut(.cancelAction)
                Button("Previous") { step(-1) }.keyboardShortcut(.leftArrow, modifiers: [])
                Button("Next") { step(1) }.keyboardShortcut(.rightArrow, modifiers: [])
                Button("Favorite") { gallery.toggleFavorite(item) }.keyboardShortcut("f", modifiers: [])
            }
            .opacity(0).frame(width: 0, height: 0)
        }
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Button(action: close) { Image(systemName: "xmark.circle.fill").font(.title2) }
                .buttonStyle(.plain)
                .help("Close (Esc)")
            VStack(alignment: .leading, spacing: 1) {
                Text(item.name).font(.headline)
                Text(item.date.formatted(date: .long, time: .shortened)
                     + " · " + ByteCountFormatter.string(fromByteCount: item.size, countStyle: .file))
                    .font(.caption).foregroundStyle(.white.opacity(0.7))
            }
            Spacer()
            Text("\(index + 1) of \(items.count)").font(.caption).foregroundStyle(.white.opacity(0.7))
            Button { step(-1) } label: { Image(systemName: "chevron.left") }
                .disabled(index == 0)
            Button { step(1) } label: { Image(systemName: "chevron.right") }
                .disabled(index == items.count - 1)
            Button { gallery.toggleFavorite(item) } label: {
                Image(systemName: gallery.isFavorite(item) ? "heart.fill" : "heart")
            }
            .help("Favorite")
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([item.url])
            } label: { Image(systemName: "folder") }
                .help("Show in Finder")
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .padding(12)
        .background(LinearGradient(colors: [.black.opacity(0.7), .clear], startPoint: .top, endPoint: .bottom))
    }

    private func step(_ delta: Int) {
        index = max(0, min(items.count - 1, index + delta))
    }
}

/// A photo, shown downsampled to screen size so large HEIC/RAW files open quickly.
/// Live Photos get a button that plays the motion clip.
private struct PhotoPane: View {
    let item: GalleryItem
    @State private var image: NSImage?
    @State private var playingLive = false

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image).resizable().scaledToFit()
            } else {
                ProgressView().colorScheme(.dark)
            }
            if playingLive, let live = item.liveVideoURL {
                VideoPane(url: live, autoplay: true) { playingLive = false }
            }
        }
        .overlay(alignment: .bottomLeading) {
            if item.isLivePhoto {
                Button { playingLive.toggle() } label: {
                    Label("LIVE", systemImage: playingLive ? "stop.circle" : "livephoto")
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(.black.opacity(0.6), in: Capsule())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .padding(16)
                .help("Play Live Photo")
            }
        }
        .task {
            image = await Task.detached(priority: .userInitiated) {
                ThumbnailCache.downsampled(item.url, maxPixels: 3200).map { NSImage(cgImage: $0, size: .zero) }
            }.value
        }
    }
}

private struct VideoPane: View {
    let url: URL
    let autoplay: Bool
    var onFinish: (() -> Void)?
    @State private var player: AVPlayer?

    var body: some View {
        Group {
            if let player { PlayerView(player: player) } else { Color.clear }
        }
        .onAppear {
            let player = AVPlayer(url: url)
            self.player = player
            if autoplay { player.play() }
        }
        .onDisappear { player?.pause() }
        .onReceive(NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime)) { _ in
            onFinish?()
        }
    }
}

/// AVKit's player in an NSViewRepresentable. SwiftUI's `VideoPlayer` aborts at launch
/// in an unbundled SwiftPM executable (it can't resolve AVPlayerView's metadata).
private struct PlayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = player
        view.controlsStyle = .floating
        return view
    }

    func updateNSView(_ view: AVPlayerView, context: Context) {
        if view.player !== player { view.player = player }
    }
}
