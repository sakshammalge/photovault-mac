import Foundation
import ImageCaptureCore

/// One photo or video on the phone's camera roll.
struct MediaItem: Identifiable, Hashable {
    let id: String
    let name: String
    let size: Int64
    let created: Date?
    let uti: String?
    let file: ICCameraFile

    var backupKey: String { BackupStore.key(name: name, size: size, created: created) }

    var isVideo: Bool {
        guard let uti else { return false }
        return uti.contains("movie") || uti.contains("video") || uti.contains("mpeg")
    }
}

struct BackupProgress {
    let total: Int
    var done = 0
    var failed: [String] = []
    var current: String?
}

enum ConnectionState: Equatable {
    case searching
    case connecting(String)
    case waitingForUnlock(String)
    case loading(String)
    case ready(String)
    case failed(String)
}

/// Finds an iPhone connected over USB and reads its camera roll via ImageCaptureCore.
/// Delegate callbacks arrive on the main thread.
final class DeviceManager: NSObject, ObservableObject {
    @Published private(set) var state: ConnectionState = .searching
    @Published private(set) var items: [MediaItem] = []
    @Published private(set) var backup: BackupProgress?
    @Published private(set) var lastBackupResult: String?

    /// Where backups are saved.
    let backupFolder = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Pictures/IphoneBackup", isDirectory: true)
    private lazy var store = BackupStore(root: backupFolder)
    private var cancelRequested = false

    private let browser = ICDeviceBrowser()
    private var camera: ICCameraDevice?

    func start() {
        guard !browser.isBrowsing else { return }
        browser.delegate = self
        browser.browsedDeviceTypeMask = ICDeviceTypeMask(
            rawValue: ICDeviceTypeMask.camera.rawValue | ICDeviceLocationTypeMask.local.rawValue
        )!
        // On macOS there is no authorization API to call: the system prompts
        // using the usage strings in Info.plist.
        browser.start()
    }

    func refresh() {
        guard let camera else { return }
        rebuildItems(from: camera)
    }

    /// Copies every item not yet in the backup folder, oldest first. Each file is
    /// downloaded to a staging folder, its size checked against the phone, then moved
    /// into YEAR/MONTH. Nothing on the phone is changed or deleted.
    func startBackup() {
        guard backup == nil else { return }
        let queue = newItems.sorted { ($0.created ?? .distantPast) < ($1.created ?? .distantPast) }
        guard !queue.isEmpty else {
            lastBackupResult = "Everything is already backed up."
            return
        }
        do {
            try store.prepare()
        } catch {
            lastBackupResult = "Can't write to \(backupFolder.path): \(error.localizedDescription)"
            return
        }
        cancelRequested = false
        lastBackupResult = nil
        backup = BackupProgress(total: queue.count)
        backUpNext(queue[...])
    }

    func cancelBackup() {
        cancelRequested = true
    }

    func isBackedUp(_ item: MediaItem) -> Bool {
        store.contains(item.backupKey)
    }

    /// Items whose own file, or a Live Photo / edit sidecar, isn't safely in the backup.
    var newItems: [MediaItem] {
        items.filter { item in
            if !store.contains(item.backupKey) { return true }
            let sidecars = item.file.sidecarFiles?.compactMap { $0 as? ICCameraFile } ?? []
            return sidecars.contains {
                !store.contains(BackupStore.key(name: $0.name ?? "Untitled", size: $0.fileSize, created: item.created))
            }
        }
    }

    /// Rechecks the backup folder against the backup record, so anything deleted or
    /// damaged there shows up as "not backed up" and is copied again by the next backup.
    func verifyBackup() {
        guard backup == nil else { return }
        let result = store.verify()
        objectWillChange.send()
        if result.problemCount == 0 {
            lastBackupResult = "Verified \(result.checked) files: all present and the right size."
            return
        }
        var summary = "Checked \(result.checked) files: \(result.missing.count) missing, \(result.mismatched.count) wrong size."
        let names = (result.missing + result.mismatched).prefix(5).map { ($0 as NSString).lastPathComponent }
        summary += " (" + names.joined(separator: ", ") + (result.problemCount > 5 ? ", …" : "") + ")"
        summary += isReadyToBackUp ? " Click Back Up to restore them." : " Connect your iPhone and back up to restore them."
        lastBackupResult = summary
    }

    private var isReadyToBackUp: Bool {
        if case .ready = state { return true }
        return false
    }

    var lastBackupDate: Date? { store.index.lastBackup }

    private func backUpNext(_ remaining: ArraySlice<MediaItem>) {
        guard let item = remaining.first, !cancelRequested, camera != nil else {
            finishBackup(cancelled: cancelRequested || camera == nil)
            return
        }
        backup?.current = item.name
        // Live Photo videos and edit files (.AAE) travel with their photo.
        let sidecars = item.file.sidecarFiles?.compactMap { $0 as? ICCameraFile } ?? []
        copyFiles([item.file] + sidecars, created: item.created) { ok in
            if ok { self.backup?.done += 1 } else { self.backup?.failed.append(item.name) }
            self.store.save()
            self.objectWillChange.send()
            self.backUpNext(remaining.dropFirst())
        }
    }

    private func copyFiles(_ files: [ICCameraFile], created: Date?, completion: @escaping (Bool) -> Void) {
        guard let file = files.first else { return completion(true) }
        copyFile(file, created: created) { ok in
            guard ok else { return completion(false) }
            self.copyFiles(Array(files.dropFirst()), created: created, completion: completion)
        }
    }

    private func copyFile(_ file: ICCameraFile, created: Date?, completion: @escaping (Bool) -> Void) {
        let name = file.name ?? "Untitled"
        let size = file.fileSize
        let key = BackupStore.key(name: name, size: size, created: created)
        if store.contains(key) { return completion(true) }
        if let existing = store.existingCopy(name: name, size: size, created: created) {
            store.record(key: key, at: existing, size: size)
            return completion(true)
        }

        let staging = store.incomingDir
        file.requestDownload(options: [
            .downloadsDirectoryURL: staging,
            .overwrite: true,
        ]) { filename, error in
            DispatchQueue.main.async {
                let downloaded = staging.appendingPathComponent(filename ?? name)
                guard error == nil, self.store.fileSize(at: downloaded) == size else {
                    NSLog("PhotoVault: \(name) failed: \(error?.localizedDescription ?? "size mismatch")")
                    try? FileManager.default.removeItem(at: downloaded)
                    return completion(false)
                }
                do {
                    let placed = try self.store.place(downloaded, name: name, created: created)
                    self.store.record(key: key, at: placed, size: size)
                    completion(true)
                } catch {
                    NSLog("PhotoVault: couldn't move \(name): \(error)")
                    completion(false)
                }
            }
        }
    }

    private func finishBackup(cancelled: Bool) {
        guard let progress = backup else { return }
        store.finish()
        var summary = "Backed up \(progress.done) of \(progress.total) items"
        if cancelled { summary += " (stopped early)" }
        if !progress.failed.isEmpty {
            summary += ". \(progress.failed.count) failed and will be retried next time: "
                + progress.failed.prefix(5).joined(separator: ", ")
        }
        lastBackupResult = summary + "."
        backup = nil
    }

    private func rebuildItems(from camera: ICCameraDevice) {
        let files = camera.mediaFiles?.compactMap { $0 as? ICCameraFile } ?? []
        items = files.map { file in
            MediaItem(
                id: "\(file.ptpObjectHandle)-\(file.name ?? "")-\(file.fileSize)",
                name: file.name ?? "Untitled",
                size: file.fileSize,
                created: file.fileCreationDate ?? file.creationDate,
                uti: file.uti,
                file: file
            )
        }
        .sorted { ($0.created ?? .distantPast) > ($1.created ?? .distantPast) }
    }
}

extension DeviceManager: ICDeviceBrowserDelegate {
    func deviceBrowser(_ browser: ICDeviceBrowser, didAdd device: ICDevice, moreComing: Bool) {
        guard camera == nil, let cam = device as? ICCameraDevice else { return }
        camera = cam
        cam.delegate = self
        // Ask for the original files (e.g. HEIC stays HEIC), regardless of the
        // phone's "Transfer to Mac or PC" setting.
        cam.mediaPresentation = .originalAssets
        state = .connecting(cam.name ?? "iPhone")
        cam.requestOpenSession()
    }

    func deviceBrowser(_ browser: ICDeviceBrowser, didRemove device: ICDevice, moreGoing: Bool) {
        if device == camera { disconnect() }
    }

    private func disconnect() {
        camera = nil
        items = []
        state = .searching
    }
}

extension DeviceManager: ICCameraDeviceDelegate {
    // MARK: ICDeviceDelegate

    func didRemove(_ device: ICDevice) {
        if device == camera { disconnect() }
    }

    func device(_ device: ICDevice, didOpenSessionWithError error: Error?) {
        let name = device.name ?? "iPhone"
        if let error {
            state = .failed("Couldn't open \(name): \(error.localizedDescription). Unlock the phone and tap Trust.")
            return
        }
        if let cam = device as? ICCameraDevice, cam.isAccessRestrictedAppleDevice {
            state = .waitingForUnlock(name)
        } else {
            state = .loading(name)
        }
    }

    func device(_ device: ICDevice, didCloseSessionWithError error: Error?) {}

    func device(_ device: ICDevice, didEncounterError error: Error?) {
        if let error { state = .failed(error.localizedDescription) }
    }

    // MARK: ICCameraDeviceDelegate

    func deviceDidBecomeReady(withCompleteContentCatalog device: ICCameraDevice) {
        rebuildItems(from: device)
        state = .ready(device.name ?? "iPhone")
    }

    func cameraDevice(_ camera: ICCameraDevice, didAdd items: [ICCameraItem]) {
        if case .ready = state { rebuildItems(from: camera) }
    }

    func cameraDevice(_ camera: ICCameraDevice, didRemove items: [ICCameraItem]) {
        rebuildItems(from: camera)
    }

    func cameraDevice(_ camera: ICCameraDevice, didRenameItems items: [ICCameraItem]) {}

    func cameraDevice(_ camera: ICCameraDevice, didReceiveThumbnail thumbnail: CGImage?, for item: ICCameraItem, error: Error?) {}

    func cameraDevice(_ camera: ICCameraDevice, didReceiveMetadata metadata: [AnyHashable: Any]?, for item: ICCameraItem, error: Error?) {}

    func cameraDeviceDidChangeCapability(_ camera: ICCameraDevice) {}

    func cameraDevice(_ camera: ICCameraDevice, didReceivePTPEvent eventData: Data) {}

    func cameraDeviceDidRemoveAccessRestriction(_ device: ICDevice) {
        state = .loading(device.name ?? "iPhone")
    }

    func cameraDeviceDidEnableAccessRestriction(_ device: ICDevice) {
        state = .waitingForUnlock(device.name ?? "iPhone")
    }
}
