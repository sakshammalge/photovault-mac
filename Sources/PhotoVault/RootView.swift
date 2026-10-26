import SwiftUI

struct RootView: View {
    enum Section: Hashable { case gallery, favorites, map, duplicates, device }

    @EnvironmentObject private var devices: DeviceManager
    @EnvironmentObject private var gallery: GalleryModel
    @State private var selection: Section? = .gallery

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 280)
        } detail: {
            switch selection ?? .gallery {
            case .gallery: GalleryView()
            case .favorites: GalleryView(favoritesOnly: true)
            case .map: MapView()
            case .duplicates: DuplicatesView()
            case .device: DeviceView()
            }
        }
    }

    private var sidebar: some View {
        List(selection: $selection) {
            SwiftUI.Section("Library") {
                Label("Photos", systemImage: "photo.on.rectangle.angled")
                    .badge(gallery.items.count)
                    .tag(Section.gallery)
                Label("Favorites", systemImage: "heart")
                    .badge(gallery.favoriteIDs.count)
                    .tag(Section.favorites)
                Label("Map", systemImage: "map")
                    .tag(Section.map)
            }
            SwiftUI.Section("Tools") {
                Label("Duplicates", systemImage: "square.on.square")
                    .tag(Section.duplicates)
            }
            SwiftUI.Section("Devices") {
                HStack(spacing: 8) {
                    Label(devices.state.deviceName ?? "iPhone", systemImage: "iphone")
                    Spacer(minLength: 0)
                    Circle()
                        .fill(devices.state.indicatorColor)
                        .frame(width: 8, height: 8)
                }
                .tag(Section.device)
                .help(devices.state.summary)
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom, spacing: 0) { backupStatus }
    }

    @ViewBuilder
    private var backupStatus: some View {
        if let progress = devices.backup {
            VStack(alignment: .leading, spacing: 6) {
                Text("Backing up…").font(.caption.weight(.semibold))
                ProgressView(value: Double(progress.done + progress.failed.count),
                             total: Double(max(progress.total, 1)))
                Text("\(progress.done + progress.failed.count) of \(progress.total)")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.bar)
        }
    }
}

extension ConnectionState {
    var deviceName: String? {
        switch self {
        case .connecting(let name), .waitingForUnlock(let name), .loading(let name), .ready(let name):
            return name
        case .searching, .failed:
            return nil
        }
    }

    var indicatorColor: Color {
        switch self {
        case .ready: return .green
        case .searching: return .secondary.opacity(0.5)
        case .failed: return .red
        default: return .orange
        }
    }

    var summary: String {
        switch self {
        case .searching: return "No iPhone connected"
        case .connecting: return "Connecting…"
        case .waitingForUnlock: return "Waiting for you to unlock the phone"
        case .loading: return "Reading the camera roll…"
        case .ready: return "Connected"
        case .failed: return "Connection problem"
        }
    }
}
