import Foundation

/// One photo or video in the backup folder.
struct GalleryItem: Identifiable, Hashable {
    /// Path relative to the backup folder.
    let id: String
    let url: URL
    let date: Date
    let isVideo: Bool
    let size: Int64
    /// The motion part of a Live Photo (the .MOV saved next to the still).
    let liveVideoURL: URL?

    var isLivePhoto: Bool { liveVideoURL != nil }
    var name: String { url.lastPathComponent }
}

struct GalleryDay: Identifiable {
    let id: Date
    let items: [GalleryItem]
}

/// Reads the backup folder (never modifies it) and groups what it finds by day.
/// Thumbnails are cached under `.photovault/thumbs` inside the same folder.
@MainActor
final class GalleryModel: ObservableObject {
    @Published private(set) var days: [GalleryDay] = []
    @Published private(set) var items: [GalleryItem] = []
    @Published private(set) var isLoading = false
    @Published private(set) var hasLoaded = false

    let root: URL
    let thumbnails: ThumbnailCache

    init(root: URL) {
        self.root = root
        thumbnails = ThumbnailCache(root: root)
    }

    func reload() {
        guard !isLoading else { return }
        isLoading = true
        let root = root
        Task {
            let scanned = await Task.detached(priority: .userInitiated) { Self.scan(root) }.value
            var calendar = Calendar.current
            calendar.timeZone = .current
            let grouped = Dictionary(grouping: scanned) { calendar.startOfDay(for: $0.date) }
            days = grouped.keys.sorted(by: >).map { day in
                GalleryDay(id: day, items: grouped[day]!.sorted { $0.date > $1.date })
            }
            items = days.flatMap(\.items)
            isLoading = false
            hasLoaded = true
        }
    }

    nonisolated private static let photoExtensions: Set<String> =
        ["heic", "heif", "jpg", "jpeg", "png", "gif", "tif", "tiff", "dng", "webp", "bmp"]
    nonisolated private static let videoExtensions: Set<String> = ["mov", "mp4", "m4v"]

    nonisolated private static func scan(_ root: URL) -> [GalleryItem] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .creationDateKey, .contentModificationDateKey, .fileSizeKey]
        guard let walker = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]
        ) else { return [] }

        struct Found { let url: URL; let date: Date; let size: Int64; let isVideo: Bool }
        var found: [Found] = []
        var stills: [String: URL] = [:]   // "dir/basename" -> still image, to pair Live Photo videos
        for case let url as URL in walker {
            let ext = url.pathExtension.lowercased()
            let isPhoto = photoExtensions.contains(ext)
            let isVideo = videoExtensions.contains(ext)
            guard isPhoto || isVideo,
                  let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true else { continue }
            let date = values.creationDate ?? values.contentModificationDate ?? .distantPast
            found.append(Found(url: url, date: date, size: Int64(values.fileSize ?? 0), isVideo: isVideo))
            if isPhoto { stills[pairKey(url)] = url }
        }

        let prefix = root.path + "/"
        var result: [GalleryItem] = []
        var liveVideos: [String: URL] = [:]
        for file in found where file.isVideo && stills[pairKey(file.url)] != nil {
            liveVideos[pairKey(file.url)] = file.url
        }
        for file in found {
            // A video with a same-named still beside it is the motion half of a Live Photo.
            if file.isVideo && liveVideos[pairKey(file.url)] != nil { continue }
            result.append(GalleryItem(
                id: file.url.path.replacingOccurrences(of: prefix, with: ""),
                url: file.url,
                date: file.date,
                isVideo: file.isVideo,
                size: file.size,
                liveVideoURL: file.isVideo ? nil : liveVideos[pairKey(file.url)]
            ))
        }
        return result
    }

    nonisolated private static func pairKey(_ url: URL) -> String {
        url.deletingPathExtension().path.lowercased()
    }
}
