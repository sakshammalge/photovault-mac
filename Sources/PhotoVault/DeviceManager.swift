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

    var isVideo: Bool {
        guard let uti else { return false }
        return uti.contains("movie") || uti.contains("video") || uti.contains("mpeg")
    }
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
    @Published var lastDownloadResult: String?

    /// Where backups are saved. Used by the test download now and the full backup later.
    let backupFolder = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Pictures/IphoneBackup", isDirectory: true)

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

    /// Copies one file to the backup folder and checks the byte count
    /// matches what the phone reported, to confirm we get untouched originals.
    func testDownload(_ item: MediaItem) {
        let dir = backupFolder
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        lastDownloadResult = "Downloading \(item.name)…"

        item.file.requestDownload(options: [
            .downloadsDirectoryURL: dir,
            .overwrite: true,
        ]) { filename, error in
            DispatchQueue.main.async {
                if let error {
                    self.lastDownloadResult = "Download failed: \(error.localizedDescription)"
                    return
                }
                let url = dir.appendingPathComponent(filename ?? item.name)
                let written = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? -1
                let match = written == item.size ? "matches the phone's original size" : "DIFFERS from the phone's size (\(item.size) bytes)"
                self.lastDownloadResult = "Saved \(url.lastPathComponent): \(written) bytes, \(match)."
            }
        }
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
