import Foundation
import ImageIO

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
    /// Ids of favorite items, kept in `.photovault/favorites.json`. Originals are never touched.
    @Published private(set) var favoriteIDs: Set<String> = []
    /// GPS positions by item id (only items that have one), read lazily by `loadLocations()`.
    @Published private(set) var locations: [String: Coordinate] = [:]
    @Published private(set) var isReadingLocations = false

    let root: URL
    let thumbnails: ThumbnailCache

    init(root: URL) {
        self.root = root
        thumbnails = ThumbnailCache(root: root)
        favoriteIDs = Self.readFavorites(root)
    }

    static func group(_ items: [GalleryItem]) -> [GalleryDay] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: items) { calendar.startOfDay(for: $0.date) }
        return grouped.keys.sorted(by: >).map { day in
            GalleryDay(id: day, items: grouped[day]!.sorted { $0.date > $1.date })
        }
    }

    // MARK: Favorites

    private var metaDir: URL { root.appendingPathComponent(".photovault", isDirectory: true) }
    private var favoritesURL: URL { metaDir.appendingPathComponent("favorites.json") }
    private var locationsURL: URL { metaDir.appendingPathComponent("locations.json") }

    func isFavorite(_ item: GalleryItem) -> Bool { favoriteIDs.contains(item.id) }

    func toggleFavorite(_ item: GalleryItem) {
        if !favoriteIDs.insert(item.id).inserted { favoriteIDs.remove(item.id) }
        let ids = favoriteIDs.sorted()
        let url = favoritesURL, dir = metaDir
        DispatchQueue.global(qos: .utility).async {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            if let data = try? JSONEncoder().encode(ids) { try? data.write(to: url, options: .atomic) }
        }
    }

    nonisolated private static func readFavorites(_ root: URL) -> Set<String> {
        let url = root.appendingPathComponent(".photovault/favorites.json")
        guard let data = try? Data(contentsOf: url),
              let ids = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return Set(ids)
    }

    // MARK: Locations

    struct Coordinate: Hashable { let latitude: Double; let longitude: Double }

    private struct CachedLocation: Codable {
        let size: Int64
        let latitude: Double?
        let longitude: Double?
    }

    /// Reads GPS tags from the photos' metadata. Results (including "no GPS") are cached
    /// in `.photovault/locations.json` so later runs only look at new files.
    func loadLocations() {
        guard !isReadingLocations else { return }
        isReadingLocations = true
        let items = items.filter { !$0.isVideo }
        let url = locationsURL, dir = metaDir
        Task {
            let result = await Task.detached(priority: .utility) { () -> [String: Coordinate] in
                var cache = (try? JSONDecoder().decode([String: CachedLocation].self, from: Data(contentsOf: url))) ?? [:]
                var changed = false
                var found: [String: Coordinate] = [:]
                for item in items {
                    if let hit = cache[item.id], hit.size == item.size {
                        if let lat = hit.latitude, let lon = hit.longitude { found[item.id] = Coordinate(latitude: lat, longitude: lon) }
                        continue
                    }
                    let point = Self.gps(of: item.url)
                    cache[item.id] = CachedLocation(size: item.size, latitude: point?.latitude, longitude: point?.longitude)
                    changed = true
                    if let point { found[item.id] = point }
                }
                if changed {
                    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                    if let data = try? JSONEncoder().encode(cache) { try? data.write(to: url, options: .atomic) }
                }
                return found
            }.value
            locations = result
            isReadingLocations = false
        }
    }

    nonisolated private static func gps(of url: URL) -> Coordinate? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let gps = props[kCGImagePropertyGPSDictionary] as? [CFString: Any],
              var lat = gps[kCGImagePropertyGPSLatitude] as? Double,
              var lon = gps[kCGImagePropertyGPSLongitude] as? Double else { return nil }
        if (gps[kCGImagePropertyGPSLatitudeRef] as? String) == "S" { lat = -lat }
        if (gps[kCGImagePropertyGPSLongitudeRef] as? String) == "W" { lon = -lon }
        guard abs(lat) <= 90, abs(lon) <= 180, !(lat == 0 && lon == 0) else { return nil }
        return Coordinate(latitude: lat, longitude: lon)
    }

    func reload() {
        guard !isLoading else { return }
        isLoading = true
        let root = root
        Task {
            let scanned = await Task.detached(priority: .userInitiated) { Self.scan(root) }.value
            days = Self.group(scanned)
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
