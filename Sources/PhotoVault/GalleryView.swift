import SwiftUI

struct GalleryView: View {
    var favoritesOnly = false

    @EnvironmentObject private var devices: DeviceManager
    @EnvironmentObject private var gallery: GalleryModel
    @AppStorage("gallery.cellSize") private var cellSize = 130.0
    @State private var viewerIndex: Int?
    @State private var searchText = ""
    @State private var useDateRange = false
    @State private var rangeStart = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
    @State private var rangeEnd = Date()
    @State private var showingRange = false

    private var isFiltering: Bool { !searchText.trimmingCharacters(in: .whitespaces).isEmpty || useDateRange }

    /// Items after the favorites, search and date-range filters.
    private var visibleItems: [GalleryItem] {
        let calendar = Calendar.current
        let from = calendar.startOfDay(for: min(rangeStart, rangeEnd))
        let to = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: max(rangeStart, rangeEnd))) ?? .distantFuture
        let tokens = searchText.lowercased().split(separator: " ").map(String.init)
        return gallery.items.filter { item in
            if favoritesOnly && !gallery.isFavorite(item) { return false }
            if useDateRange && !(item.date >= from && item.date < to) { return false }
            return tokens.allSatisfy { Self.searchText(for: item).contains($0) }
        }
    }

    /// What a search can match: the date written out ("monday october 14 2026"), as
    /// "2026-10-14", and the file name. So "oct 2026" or "2026-10" both work.
    private static func searchText(for item: GalleryItem) -> String {
        let written = item.date.formatted(.dateTime.weekday(.wide).month(.wide).day().year())
        let iso = item.date.formatted(.iso8601.year().month().day())
        return "\(written) \(iso) \(item.name)".lowercased()
    }

    var body: some View {
        ZStack {
            content
            if let index = viewerIndex, !visibleItems.isEmpty {
                let shown = visibleItems
                ViewerView(items: shown, index: Binding(
                    get: { min(index, shown.count - 1) },
                    set: { viewerIndex = $0 }
                )) { viewerIndex = nil }
                .transition(.opacity)
            }
        }
        .navigationTitle(favoritesOnly ? "Favorites" : "Photos")
        .navigationSubtitle(gallery.items.isEmpty ? "" : (isFiltering || favoritesOnly
            ? "\(visibleItems.count) of \(gallery.items.count) items" : "\(gallery.items.count) items"))
        .searchable(text: $searchText, placement: .toolbar, prompt: "Search by date, e.g. “oct 2026”")
        .animation(.easeInOut(duration: 0.15), value: viewerIndex == nil)
        .toolbar {
            ToolbarItemGroup {
                Button { showingRange.toggle() } label: {
                    Image(systemName: useDateRange ? "calendar.badge.clock" : "calendar")
                }
                .help("Filter by date range")
                .popover(isPresented: $showingRange, arrowEdge: .bottom) {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle("Only show a date range", isOn: $useDateRange)
                        DatePicker("From", selection: $rangeStart, displayedComponents: .date).disabled(!useDateRange)
                        DatePicker("To", selection: $rangeEnd, displayedComponents: .date).disabled(!useDateRange)
                    }
                    .padding(14)
                    .frame(width: 240)
                }
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
        if !gallery.items.isEmpty && visibleItems.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: favoritesOnly && !isFiltering ? "heart" : "magnifyingglass")
                    .font(.system(size: 48, weight: .light))
                    .foregroundStyle(.secondary)
                Text(favoritesOnly && !isFiltering ? "No Favorites Yet" : "No Matches").font(.title2.weight(.semibold))
                Text(favoritesOnly && !isFiltering
                     ? "Click the heart on a photo, or right-click it and choose Favorite."
                     : "Try a different search or date range.")
                    .foregroundStyle(.secondary)
            }
            .padding(40)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if gallery.items.isEmpty {
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
            let shown = visibleItems
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: cellSize), spacing: 2)],
                          spacing: 2, pinnedViews: [.sectionHeaders]) {
                    ForEach(GalleryModel.group(shown)) { day in
                        Section {
                            ForEach(day.items) { item in
                                ThumbnailCell(item: item)
                                    .onTapGesture {
                                        viewerIndex = shown.firstIndex(of: item)
                                    }
                                    .contextMenu {
                                        Button(gallery.isFavorite(item) ? "Remove from Favorites" : "Favorite") {
                                            gallery.toggleFavorite(item)
                                        }
                                        Button("Show in Finder") {
                                            NSWorkspace.shared.activateFileViewerSelecting([item.url])
                                        }
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

struct ThumbnailCell: View {
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
            .overlay(alignment: .bottomTrailing) {
                if gallery.isFavorite(item) {
                    Image(systemName: "heart.fill")
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
