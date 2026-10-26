import Foundation

/// An iPhone PhotoVault has backed up, and where its backup lives.
struct KnownDevice: Codable, Identifiable, Hashable {
    /// Stable across renames and reconnects (serial number / UUID reported by the phone).
    var id: String
    /// The phone's current name, refreshed each time it connects.
    var name: String
    /// Absolute path of the backup folder, normally `~/Pictures/{name}`.
    var path: String

    var folder: URL { URL(fileURLWithPath: path, isDirectory: true) }
}

/// Remembers every device that has been backed up, one folder each, and which one the
/// gallery is showing. Nothing here moves or deletes files.
final class DeviceLibrary: ObservableObject {
    /// The pre-multi-device backup location.
    static let legacyID = "legacy-IphoneBackup"

    @Published private(set) var devices: [KnownDevice] = []
    @Published var selectedID: String? {
        didSet { UserDefaults.standard.set(selectedID, forKey: Self.selectedKey) }
    }

    private static let devicesKey = "knownDevices"
    private static let selectedKey = "selectedDeviceID"
    private let picturesFolder: URL

    init(picturesFolder: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Pictures", isDirectory: true)) {
        self.picturesFolder = picturesFolder
        if let data = UserDefaults.standard.data(forKey: Self.devicesKey),
           let saved = try? JSONDecoder().decode([KnownDevice].self, from: data) {
            devices = saved
        }
        // An existing ~/Pictures/IphoneBackup stays visible, untouched, until it is
        // handed to a phone (see `claimLegacy`).
        let legacy = legacyFolder
        if !devices.contains(where: { $0.path == legacy.path }),
           FileManager.default.fileExists(atPath: legacy.path),
           !devices.contains(where: { $0.id == Self.legacyID }) {
            devices.append(KnownDevice(id: Self.legacyID, name: "IphoneBackup", path: legacy.path))
            save()
        }
        let saved = UserDefaults.standard.string(forKey: Self.selectedKey)
        selectedID = devices.contains(where: { $0.id == saved }) ? saved : devices.first?.id
    }

    var selected: KnownDevice? { devices.first { $0.id == selectedID } }

    private var legacyFolder: URL { picturesFolder.appendingPathComponent("IphoneBackup", isDirectory: true) }

    /// The unclaimed legacy library, offered to the first phone that connects.
    var unclaimedLegacy: KnownDevice? {
        devices.count == 1 ? devices.first { $0.id == Self.legacyID } : nil
    }

    func device(id: String) -> KnownDevice? { devices.first { $0.id == id } }

    /// A phone that connected before keeps its folder even if it was renamed; only the
    /// display name follows the phone.
    func existing(id: String, name: String) -> KnownDevice? {
        guard let index = devices.firstIndex(where: { $0.id == id }) else { return nil }
        if devices[index].name != name {
            devices[index].name = name
            save()
        }
        return devices[index]
    }

    /// Registers a new phone with its own `~/Pictures/{name}` folder.
    @discardableResult
    func add(id: String, name: String) -> KnownDevice {
        let device = KnownDevice(id: id, name: name, path: uniqueFolder(for: name).path)
        devices.append(device)
        save()
        return device
    }

    /// Hands the existing IphoneBackup folder to this phone, without moving any files.
    @discardableResult
    func claimLegacy(id: String, name: String) -> KnownDevice? {
        guard let index = devices.firstIndex(where: { $0.id == Self.legacyID }) else { return nil }
        devices[index].id = id
        devices[index].name = name
        if selectedID == Self.legacyID { selectedID = id }
        save()
        return devices[index]
    }

    /// Folder-safe version of a device name: no path separators, no leading dots.
    static func sanitize(_ name: String) -> String {
        var cleaned = name.map { "/:\\\0".contains($0) || $0.isNewline ? "-" : String($0) }.joined()
        cleaned = cleaned.trimmingCharacters(in: .whitespaces)
        while cleaned.hasPrefix(".") { cleaned.removeFirst() }
        cleaned = cleaned.trimmingCharacters(in: .whitespaces)
        return cleaned.isEmpty ? "iPhone" : String(cleaned.prefix(100))
    }

    private func uniqueFolder(for name: String) -> URL {
        let base = Self.sanitize(name)
        let taken = Set(devices.map { $0.path.lowercased() })
        var candidate = picturesFolder.appendingPathComponent(base, isDirectory: true)
        var n = 2
        while taken.contains(candidate.path.lowercased()) {
            candidate = picturesFolder.appendingPathComponent("\(base) (\(n))", isDirectory: true)
            n += 1
        }
        return candidate
    }

    private func save() {
        if let data = try? JSONEncoder().encode(devices) {
            UserDefaults.standard.set(data, forKey: Self.devicesKey)
        }
    }
}
