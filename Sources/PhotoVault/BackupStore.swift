import Foundation

/// One file copied into the backup folder.
struct BackupRecord: Codable {
    /// Path relative to the backup folder, e.g. "2026/10/IMG_1234.HEIC".
    let path: String
    let size: Int64
    let backedUpAt: Date
}

/// What has already been backed up, saved as `.photovault/index.json` inside the backup folder.
struct BackupIndex: Codable {
    var records: [String: BackupRecord] = [:]
    var lastBackup: Date?
}

struct VerifyResult {
    let checked: Int
    var missing: [String] = []
    var mismatched: [String] = []
    var problemCount: Int { missing.count + mismatched.count }
}

/// Tracks which phone files are already in the backup folder and where new ones go.
final class BackupStore {
    let root: URL
    private(set) var index: BackupIndex

    private let fm = FileManager.default
    private var metaDir: URL { root.appendingPathComponent(".photovault", isDirectory: true) }
    private var indexURL: URL { metaDir.appendingPathComponent("index.json") }
    /// Files land here first and are moved into place only after their size checks out.
    var incomingDir: URL { metaDir.appendingPathComponent("incoming", isDirectory: true) }

    init(root: URL) {
        self.root = root
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let url = root.appendingPathComponent(".photovault/index.json")
        index = (try? decoder.decode(BackupIndex.self, from: Data(contentsOf: url))) ?? BackupIndex()
    }

    /// Identifies a phone file across connections. iPhone names repeat (IMG_0001 again
    /// after IMG_9999), so the size and capture time are part of the key.
    static func key(name: String, size: Int64, created: Date?) -> String {
        let time = created.map { String(Int($0.timeIntervalSince1970)) } ?? "nodate"
        return "\(name)|\(size)|\(time)"
    }

    func contains(_ key: String) -> Bool {
        index.records[key] != nil
    }

    func prepare() throws {
        try fm.createDirectory(at: incomingDir, withIntermediateDirectories: true)
    }

    /// The YEAR/MONTH folder a file taken at `created` belongs in.
    func folder(for created: Date?) -> URL {
        guard let created else { return root.appendingPathComponent("Undated", isDirectory: true) }
        let parts = Calendar.current.dateComponents([.year, .month], from: created)
        return root
            .appendingPathComponent(String(format: "%04d", parts.year ?? 0), isDirectory: true)
            .appendingPathComponent(String(format: "%02d", parts.month ?? 0), isDirectory: true)
    }

    /// A file already in the backup folder (e.g. from an earlier manual copy) with the
    /// same name and size, so it doesn't need downloading again.
    func existingCopy(name: String, size: Int64, created: Date?) -> URL? {
        for dir in [folder(for: created), root] {
            let url = dir.appendingPathComponent(name)
            if fileSize(at: url) == size { return url }
        }
        return nil
    }

    /// Moves a verified download into its YEAR/MONTH folder without overwriting
    /// anything, and stamps it with the capture date.
    func place(_ downloaded: URL, name: String, created: Date?) throws -> URL {
        let dir = folder(for: created)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        var dest = dir.appendingPathComponent(name)
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var n = 2
        while fm.fileExists(atPath: dest.path) {
            dest = dir.appendingPathComponent(ext.isEmpty ? "\(base) (\(n))" : "\(base) (\(n)).\(ext)")
            n += 1
        }
        try fm.moveItem(at: downloaded, to: dest)
        if let created {
            try? fm.setAttributes([.creationDate: created, .modificationDate: created], ofItemAtPath: dest.path)
        }
        return dest
    }

    func record(key: String, at url: URL, size: Int64) {
        let rel = url.path.replacingOccurrences(of: root.path + "/", with: "")
        index.records[key] = BackupRecord(path: rel, size: size, backedUpAt: Date())
    }

    /// Checks every record against the backup folder. Records whose file is gone or has
    /// a different size are dropped so the next backup copies them again. Files on
    /// disk are never touched.
    func verify() -> VerifyResult {
        var result = VerifyResult(checked: index.records.count)
        for (key, record) in index.records {
            let url = root.appendingPathComponent(record.path)
            guard let size = fileSize(at: url) else {
                result.missing.append(record.path)
                index.records[key] = nil
                continue
            }
            if size != record.size {
                result.mismatched.append(record.path)
                index.records[key] = nil
            }
        }
        result.missing.sort()
        result.mismatched.sort()
        if result.problemCount > 0 { save() }
        return result
    }

    func finish() {
        index.lastBackup = Date()
        save()
    }

    func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            try fm.createDirectory(at: metaDir, withIntermediateDirectories: true)
            try encoder.encode(index).write(to: indexURL, options: .atomic)
        } catch {
            NSLog("PhotoVault: couldn't save backup index: \(error)")
        }
    }

    func fileSize(at url: URL) -> Int64? {
        (try? fm.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value
    }
}
