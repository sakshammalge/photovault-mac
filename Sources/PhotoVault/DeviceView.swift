import SwiftUI

struct DeviceView: View {
    @EnvironmentObject private var devices: DeviceManager
    @State private var selection: MediaItem.ID?

    var body: some View {
        VStack(spacing: 0) {
            if case .ready = devices.state {
                VStack(spacing: 16) {
                    header
                    statusCard
                }
                .padding(20)
                Divider()
                table
            } else {
                placeholder
            }
        }
        .navigationTitle(devices.state.deviceName ?? "iPhone")
        .toolbar {
            ToolbarItem {
                Button { devices.refresh() } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                    .help("Re-read the camera roll")
                    .disabled(!isReady || devices.backup != nil)
            }
        }
    }

    // MARK: Connected

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: "iphone")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(.tint)
                .frame(width: 52, height: 52)
                .background(.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(devices.state.deviceName ?? "iPhone").font(.title2.weight(.semibold))
                HStack(spacing: 6) {
                    Circle().fill(.green).frame(width: 7, height: 7)
                    Text("Connected").foregroundStyle(.secondary)
                }
                .font(.callout)
            }
            Spacer()
            HStack(spacing: 24) {
                stat("\(photoCount)", "Photos")
                stat("\(videoCount)", "Videos")
                stat(ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file), "Total")
            }
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.title3.weight(.semibold)).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let progress = devices.backup {
                backupProgress(progress)
            } else {
                backupActions
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func backupProgress(_ progress: BackupProgress) -> some View {
        let finished = progress.done + progress.failed.count
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Backing up your photos").font(.headline)
                Spacer()
                Text("\(finished) of \(progress.total)").monospacedDigit().foregroundStyle(.secondary)
            }
            ProgressView(value: Double(finished), total: Double(max(progress.total, 1)))
            HStack {
                Text(progress.current ?? " ")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button("Stop") { devices.cancelBackup() }
            }
        }
    }

    @ViewBuilder
    private var backupActions: some View {
        let count = devices.newItems.count
        HStack(spacing: 12) {
            Image(systemName: count == 0 ? "checkmark.circle.fill" : "arrow.down.circle.fill")
                .font(.system(size: 28))
                .foregroundStyle(count == 0 ? Color.green : Color.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(count == 0 ? "Everything is backed up" : "\(count) item\(count == 1 ? "" : "s") not backed up yet")
                    .font(.headline)
                Text(lastBackupText).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Verify Backup") { devices.verifyBackup() }
                .help("Check that every backed-up file is still in the backup folder")
            Button(count == 0 ? "Up to Date" : "Back Up \(count) New Item\(count == 1 ? "" : "s")") {
                devices.startBackup()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(count == 0)
        }
        Toggle("Back up automatically when this iPhone connects", isOn: $devices.autoBackupEnabled)
            .toggleStyle(.checkbox)
            .font(.callout)
        if let result = devices.lastBackupResult {
            Text(result).font(.callout).foregroundStyle(.secondary)
        }
    }

    private var table: some View {
        Table(devices.items, selection: $selection) {
            TableColumn("") { item in
                if devices.isBackedUp(item) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .help("Backed up")
                } else {
                    Image(systemName: "circle.dashed")
                        .foregroundStyle(.tertiary)
                        .help("Not backed up yet")
                }
            }
            .width(24)
            TableColumn("Name") { item in
                Label(item.name, systemImage: item.isVideo ? "video" : "photo")
            }
            TableColumn("Taken") { item in
                Text(item.created.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "—")
            }
            TableColumn("Size") { item in
                Text(ByteCountFormatter.string(fromByteCount: item.size, countStyle: .file))
                    .foregroundStyle(.secondary)
            }
            .width(90)
            TableColumn("Type") { item in
                Text(item.uti ?? "—").foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Not connected

    @ViewBuilder
    private var placeholder: some View {
        VStack(spacing: 10) {
            switch devices.state {
            case .searching:
                Image(systemName: "iphone.slash").font(.system(size: 44, weight: .light)).foregroundStyle(.secondary)
                Text("No iPhone Connected").font(.title2.weight(.semibold))
                Text("Connect your iPhone to this Mac with a cable to back up its photos.")
                    .foregroundStyle(.secondary)
            case .connecting(let name):
                ProgressView().controlSize(.large)
                Text("Connecting to \(name)…").font(.title3)
            case .waitingForUnlock(let name):
                Image(systemName: "lock.iphone").font(.system(size: 44, weight: .light)).foregroundStyle(.orange)
                Text("Unlock \(name)").font(.title2.weight(.semibold))
                Text("Tap **Trust** on the phone if it asks.").foregroundStyle(.secondary)
            case .loading(let name):
                ProgressView().controlSize(.large)
                Text("Reading the camera roll on \(name)…").font(.title3)
                Text("This can take a minute for large libraries.").foregroundStyle(.secondary)
            case .failed(let message):
                Image(systemName: "exclamationmark.triangle").font(.system(size: 44, weight: .light)).foregroundStyle(.red)
                Text("Something Went Wrong").font(.title2.weight(.semibold))
                Text(message).foregroundStyle(.secondary).multilineTextAlignment(.center)
            case .ready:
                EmptyView()
            }
        }
        .multilineTextAlignment(.center)
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Helpers

    private var isReady: Bool {
        if case .ready = devices.state { return true }
        return false
    }

    private var videoCount: Int { devices.items.filter(\.isVideo).count }
    private var photoCount: Int { devices.items.count - videoCount }
    private var totalSize: Int64 { devices.items.reduce(Int64(0)) { $0 + $1.size } }

    private var lastBackupText: String {
        let date = devices.lastBackupDate.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "never"
        return "Last backup \(date) · saving to \(((devices.backupFolder?.path ?? "") as NSString).abbreviatingWithTildeInPath)"
    }
}
