import SwiftUI

struct RootView: View {
    enum Section: Hashable { case gallery, favorites, map, duplicates, device }

    @EnvironmentObject private var library: DeviceLibrary
    @EnvironmentObject private var devices: DeviceManager
    @EnvironmentObject private var gallery: GalleryModel
    @State private var selection: Section? = .gallery

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 280)
        } detail: {
            Group {
                switch selection ?? .gallery {
                case .gallery: GalleryView()
                case .favorites: GalleryView(favoritesOnly: true)
                case .map: MapView()
                case .duplicates: DuplicatesView()
                case .device: DeviceView()
                }
            }
            .id(gallery.root)   // start each view fresh for the chosen device
        }
        .onAppear { showSelectedDevice() }
        .onChange(of: library.selectedID) { _ in showSelectedDevice() }
        .alert("Use your existing backup for \(devices.pendingDeviceName ?? "this iPhone")?",
               isPresented: Binding(get: { devices.legacyPrompt != nil }, set: { _ in })) {
            Button("Use Existing Folder") { devices.resolveLegacy(useExisting: true) }
            Button("Start a New Folder") { devices.resolveLegacy(useExisting: false) }
        } message: {
            let folder = ((devices.legacyPrompt ?? "") as NSString).abbreviatingWithTildeInPath
            Text("Photos already saved in \(folder) can become this iPhone's backup. No files are moved or changed. Otherwise this iPhone gets its own folder in Pictures, and the old folder stays available in the device menu.")
        }
    }

    private func showSelectedDevice() {
        if let folder = library.selected?.folder { gallery.switchRoot(to: folder) }
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
        .safeAreaInset(edge: .top, spacing: 0) { devicePicker.padding([.horizontal, .top], 12).padding(.bottom, 4) }
        .safeAreaInset(edge: .bottom, spacing: 0) { backupStatus }
    }

    /// Chooses whose backup the gallery, favorites, map and duplicates views show.
    private var devicePicker: some View {
        Picker("", selection: Binding(
            get: { library.selectedID ?? "" },
            set: { library.selectedID = $0 }
        )) {
            ForEach(library.devices) { device in
                Label(device.name, systemImage: "iphone").tag(device.id)
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .disabled(library.devices.isEmpty)
        .help("Which iPhone's backup to browse")
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
