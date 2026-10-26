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
                .disabled(!isReady || devices.backup != nil)
        }
    }

    private var table: some View {
        Table(devices.items, selection: $selection) {
            TableColumn("") { item in
                if devices.isBackedUp(item) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .help("Backed up")
                }
            }
            .width(20)
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
        HStack(spacing: 12) {
            if let progress = devices.backup {
                ProgressView(value: Double(progress.done + progress.failed.count), total: Double(progress.total))
                    .frame(maxWidth: 240)
                Text(progressText(progress))
                    .font(.callout)
                    .monospacedDigit()
                    .lineLimit(1)
                Spacer()
                Button("Stop") { devices.cancelBackup() }
            } else {
                let count = devices.newItems.count
                Button(count == 0 ? "Up to date" : "Back Up \(count) New Item\(count == 1 ? "" : "s")") {
                    devices.startBackup()
                }
                .buttonStyle(.borderedProminent)
                .disabled(count == 0)
                Button("Verify Backup") { devices.verifyBackup() }
                    .help("Check that every backed-up file is still in the backup folder")
                VStack(alignment: .leading, spacing: 2) {
                    if let result = devices.lastBackupResult {
                        Text(result).font(.callout)
                    }
                    Text(lastBackupText).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
    }

    private func progressText(_ progress: BackupProgress) -> String {
        let count = "\(progress.done + progress.failed.count) of \(progress.total)"
        guard let current = progress.current else { return count }
        return count + " · " + current
    }

    private var lastBackupText: String {
        let date = devices.lastBackupDate.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "never"
        return "Saving to \(devices.backupFolder.path) · last backup \(date)"
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
            + " · \(devices.newItems.count) not backed up yet"
    }
}
