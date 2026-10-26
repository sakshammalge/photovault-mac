import SwiftUI

struct GalleryView: View {
    @EnvironmentObject private var devices: DeviceManager
    @EnvironmentObject private var gallery: GalleryModel
    @AppStorage("gallery.cellSize") private var cellSize = 130.0
    @State private var viewerIndex: Int?

    var body: some View {
        ZStack {
            content
            if let index = viewerIndex {
                ViewerView(items: gallery.items, index: Binding(
                    get: { min(index, gallery.items.count - 1) },
                    set: { viewerIndex = $0 }
                )) { viewerIndex = nil }
                .transition(.opacity)
            }
        }
        .navigationTitle("Photos")
        .navigationSubtitle(gallery.items.isEmpty ? "" : "\(gallery.items.count) items")
        .animation(.easeInOut(duration: 0.15), value: viewerIndex == nil)
        .toolbar {
            ToolbarItemGroup {
                Slider(value: $cellSize, in: 80...320)
                    .frame(width: 110)
                    .help("Thumbnail size")
                Button { gallery.reload() } label: { Image(systemName: "arrow.clockwise") }
                    .help("Rescan the backup folder")
            }
        }
        .onAppear { if !gallery.hasLoaded { gallery.reload() } }
        .onChange(of: devices.backup == nil) { idle in
            if idle { gallery.reload() }   // a backup just finished or was stopped
        }
    }

    @ViewBuilder
    private var content: some View {
        if gallery.items.isEmpty {
            VStack(spacing: 10) {
                if gallery.isLoading || !gallery.hasLoaded {
                    ProgressView().controlSize(.large)
                } else {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 48, weight: .light))
                        .foregroundStyle(.secondary)
                    Text("No Photos Yet").font(.title2.weight(.semibold))
                    Text("Connect your iPhone and back it up, or copy photos into\n\((gallery.root.path as NSString).abbreviatingWithTildeInPath).")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Show Backup Folder") { NSWorkspace.shared.open(gallery.root) }
                        .padding(.top, 4)
                }
            }
            .padding(40)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: cellSize), spacing: 2)],
                          spacing: 2, pinnedViews: [.sectionHeaders]) {
                    ForEach(gallery.days) { day in
                        Section {
                            ForEach(day.items) { item in
                                ThumbnailCell(item: item)
                                    .onTapGesture {
                                        viewerIndex = gallery.items.firstIndex(of: item)
                                    }
                            }
                        } header: {
                            HStack {
                                Text(day.id.formatted(date: .complete, time: .omitted)).font(.headline)
                                Text("\(day.items.count)").font(.subheadline).foregroundStyle(.secondary)
                                Spacer()
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(.bar)
                        }
                    }
                }
            }
        }
    }
}

private struct ThumbnailCell: View {
    @EnvironmentObject private var gallery: GalleryModel
    let item: GalleryItem
    @State private var image: NSImage?

    var body: some View {
        Color.secondary.opacity(0.12)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let image {
                    Image(nsImage: image).resizable().scaledToFill()
                }
            }
            .overlay(alignment: .bottomLeading) {
                if item.isVideo || item.isLivePhoto {
                    Image(systemName: item.isVideo ? "play.fill" : "livephoto")
                        .font(.caption)
                        .foregroundStyle(.white)
                        .shadow(radius: 2)
                        .padding(5)
                }
            }
            .clipped()
            .contentShape(Rectangle())
            .task(id: item.id) {
                image = await gallery.thumbnails.thumbnail(for: item)
            }
    }
}
