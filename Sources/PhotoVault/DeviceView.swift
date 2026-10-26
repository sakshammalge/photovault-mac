import SwiftUI

struct DeviceView: View {
    @EnvironmentObject private var devices: DeviceManager
    @State private var selection: MediaItem.ID?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if case .ready = devices.state {
                table
                footer
            } else {
                Spacer()
                statusMessage
                    .frame(maxWidth: .infinity)
                Spacer()
            }
        }
        .padding()
    }

    private var header: some View {
        HStack {
            Image(systemName: "iphone")
                .font(.title2)
            VStack(alignment: .leading) {
                Text(title).font(.headline)
                Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Refresh") { devices.refresh() }
                .disabled(!isReady)
        }
    }

    private var table: some View {
        Table(devices.items, selection: $selection) {
            TableColumn("Name") { item in
                Label(item.name, systemImage: item.isVideo ? "video" : "photo")
            }
            TableColumn("Taken") { item in
                Text(item.created.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "—")
            }
            TableColumn("Size") { item in
                Text(ByteCountFormatter.string(fromByteCount: item.size, countStyle: .file))
            }
            .width(90)
            TableColumn("Type") { item in
                Text(item.uti ?? "—").foregroundStyle(.secondary)
            }
        }
    }

    private var footer: some View {
        HStack {
            Button("Test download selected") {
                if let item = devices.items.first(where: { $0.id == selection }) {
                    devices.testDownload(item)
                }
            }
            .disabled(selection == nil)
            if let result = devices.lastDownloadResult {
                Text(result).font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var statusMessage: some View {
        VStack(spacing: 8) {
            switch devices.state {
            case .searching:
                ProgressView()
                Text("Plug in your iPhone with a cable.")
            case .connecting(let name):
                ProgressView()
                Text("Connecting to \(name)…")
            case .waitingForUnlock(let name):
                Image(systemName: "lock.iphone").font(.largeTitle)
                Text("Unlock \(name) and tap **Trust** if asked.")
            case .loading(let name):
                ProgressView()
                Text("Reading the camera roll on \(name)…")
            case .failed(let message):
                Image(systemName: "exclamationmark.triangle").font(.largeTitle)
                Text(message).multilineTextAlignment(.center)
            case .ready:
                EmptyView()
            }
        }
    }

    private var isReady: Bool {
        if case .ready = devices.state { return true }
        return false
    }

    private var title: String {
        switch devices.state {
        case .ready(let name), .loading(let name), .connecting(let name), .waitingForUnlock(let name):
            return name
        default:
            return "No iPhone connected"
        }
    }

    private var subtitle: String {
        guard isReady else { return "PhotoVault" }
        let videos = devices.items.filter(\.isVideo).count
        let total = devices.items.reduce(Int64(0)) { $0 + $1.size }
        return "\(devices.items.count - videos) photos, \(videos) videos · "
            + ByteCountFormatter.string(fromByteCount: total, countStyle: .file)
    }
}
