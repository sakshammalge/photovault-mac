import CoreGraphics
import CryptoKit
import Foundation

enum DuplicateKind { case identical, similar }

/// Photos that look like each other. This only reports; nothing is ever deleted or moved.
struct DuplicateGroup: Identifiable {
    let id = UUID()
    let kind: DuplicateKind
    let items: [GalleryItem]
    /// Space the extra copies take up (everything but the largest file).
    var reclaimableBytes: Int64 { items.map(\.size).reduce(0, +) - (items.map(\.size).max() ?? 0) }
}

struct DuplicateProgress {
    var stage: String
    var done: Int
    var total: Int
}

/// Finds duplicates in two passes: identical files (same size, then same SHA-256), then
/// photos that merely look alike (a 64-bit difference hash compared by Hamming distance).
enum DuplicateFinder {
    /// Hashes that differ in at most this many of 64 bits count as "similar".
    static let similarityThreshold = 4

    static func find(in items: [GalleryItem], progress: @escaping @Sendable (DuplicateProgress) -> Void) -> [DuplicateGroup] {
        // Pass 1: identical content. Only files that share a size can be identical.
        let sizeGroups = Dictionary(grouping: items, by: \.size).values.filter { $0.count > 1 }
        let candidates = sizeGroups.flatMap { $0 }
        var done = 0
        var byHash: [String: [GalleryItem]] = [:]
        for item in candidates {
            if Task.isCancelled { return [] }
            if let hash = sha256(of: item.url) { byHash[hash, default: []].append(item) }
            done += 1
            if done % 20 == 0 || done == candidates.count {
                progress(DuplicateProgress(stage: "Comparing file contents", done: done, total: candidates.count))
            }
        }
        // A unit is a set of identical files, or a single file.
        var units: [[GalleryItem]] = byHash.values.filter { $0.count > 1 }.map { $0.sorted { $0.date < $1.date } }
        let identicalIDs = Set(units.flatMap { $0.map(\.id) })
        let identicalGroups = units.map { DuplicateGroup(kind: .identical, items: $0) }
        units += items.filter { !identicalIDs.contains($0.id) }.map { [$0] }
        // Only one file from each identical set needs a perceptual hash.
        let hashable = units.indices.filter { !units[$0][0].isVideo }

        // Pass 2: look-alikes among photos.
        var hashes: [(unit: Int, hash: UInt64)] = []
        for (n, unit) in hashable.enumerated() {
            if Task.isCancelled { return [] }
            if let hash = differenceHash(of: units[unit][0].url) { hashes.append((unit, hash)) }
            if n % 20 == 0 || n == hashable.count - 1 {
                progress(DuplicateProgress(stage: "Comparing how photos look", done: n + 1, total: hashable.count))
            }
        }
        var parent = Array(units.indices)
        func root(_ i: Int) -> Int {
            var i = i
            while parent[i] != i { parent[i] = parent[parent[i]]; i = parent[i] }
            return i
        }
        for a in hashes.indices {
            for b in hashes.indices where b > a {
                if (hashes[a].hash ^ hashes[b].hash).nonzeroBitCount <= similarityThreshold {
                    parent[root(hashes[a].unit)] = root(hashes[b].unit)
                }
            }
        }
        var clusters: [Int: [Int]] = [:]
        for entry in hashes { clusters[root(entry.unit), default: []].append(entry.unit) }
        var similarGroups: [DuplicateGroup] = []
        var inSimilar = Set<Int>()
        for members in clusters.values where members.count > 1 {
            inSimilar.formUnion(members)
            similarGroups.append(DuplicateGroup(kind: .similar,
                                                items: members.flatMap { units[$0] }.sorted { $0.date < $1.date }))
        }
        // Identical sets that matched nothing else stay "identical"; merged ones became "similar".
        let keptIdentical = identicalGroups.enumerated().filter { !inSimilar.contains($0.offset) }.map(\.element)
        return (keptIdentical + similarGroups).sorted { $0.reclaimableBytes > $1.reclaimableBytes }
    }

    private static func sha256(of url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try? handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// dHash: shrink to 9x8 grey, then one bit per pixel for "brighter than its right neighbour".
    private static func differenceHash(of url: URL) -> UInt64? {
        guard let image = ThumbnailCache.downsampled(url, maxPixels: 64) else { return nil }
        var pixels = [UInt8](repeating: 0, count: 9 * 8)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: 9, height: 8, bitsPerComponent: 8,
                                          bytesPerRow: 9, space: CGColorSpaceCreateDeviceGray(),
                                          bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: 9, height: 8))
            return true
        }
        guard drawn else { return nil }
        var hash: UInt64 = 0
        for row in 0..<8 {
            for col in 0..<8 {
                hash <<= 1
                if pixels[row * 9 + col] > pixels[row * 9 + col + 1] { hash |= 1 }
            }
        }
        return hash
    }
}

@MainActor
final class DuplicateModel: ObservableObject {
    @Published private(set) var groups: [DuplicateGroup] = []
    @Published private(set) var progress: DuplicateProgress?
    @Published private(set) var hasRun = false
    private var worker: Task<[DuplicateGroup], Never>?

    var isRunning: Bool { progress != nil }

    func scan(_ items: [GalleryItem]) {
        guard !isRunning else { return }
        progress = DuplicateProgress(stage: "Starting", done: 0, total: 0)
        let worker = Task.detached(priority: .utility) {
            DuplicateFinder.find(in: items) { update in
                Task { @MainActor in if self.worker != nil { self.progress = update } }
            }
        }
        self.worker = worker
        Task {
            let found = await worker.value
            if !worker.isCancelled { groups = found; hasRun = true }
            self.worker = nil
            progress = nil
        }
    }

    func cancel() {
        worker?.cancel()
    }
}
