import AppKit
import AVFoundation
import CryptoKit
import ImageIO
import UniformTypeIdentifiers

/// Makes small preview images and keeps them in memory and on disk so scrolling a big
/// library stays fast. Originals are only read; cached JPEGs live in `.photovault/thumbs`.
final class ThumbnailCache {
    /// Longest edge of a cached thumbnail, in pixels.
    static let pixelSize = 512

    private let memory = NSCache<NSString, NSImage>()
    private let directory: URL
    private let limiter = Limiter(count: 4)

    init(root: URL) {
        directory = root.appendingPathComponent(".photovault/thumbs", isDirectory: true)
        memory.countLimit = 3000
    }

    func thumbnail(for item: GalleryItem) async -> NSImage? {
        let key = cacheKey(for: item)
        if let image = memory.object(forKey: key as NSString) { return image }

        await limiter.acquire()
        defer { Task { await limiter.release() } }
        if Task.isCancelled { return nil }
        if let image = memory.object(forKey: key as NSString) { return image }

        let file = directory.appendingPathComponent(key + ".jpg")
        var cgImage = await Task.detached(priority: .userInitiated) { Self.downsampled(file, maxPixels: Self.pixelSize) }.value
        if cgImage == nil {
            cgImage = item.isVideo
                ? await Self.videoFrame(item.url)
                : await Task.detached(priority: .userInitiated) { Self.downsampled(item.url, maxPixels: Self.pixelSize) }.value
            if let cgImage { writeToDisk(cgImage, at: file) }
        }
        guard let cgImage else { return nil }
        let image = NSImage(cgImage: cgImage, size: .zero)
        memory.setObject(image, forKey: key as NSString)
        return image
    }

    private func cacheKey(for item: GalleryItem) -> String {
        let source = "\(item.id)|\(item.size)|\(Int(item.date.timeIntervalSince1970))"
        return SHA256.hash(data: Data(source.utf8)).prefix(16).map { String(format: "%02x", $0) }.joined()
    }

    private func writeToDisk(_ image: CGImage, at url: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
        CGImageDestinationFinalize(destination)
    }

    /// Decodes a downscaled copy straight from the file (works for HEIC) with the
    /// EXIF rotation applied, without loading the full-size image.
    static func downsampled(_ url: URL, maxPixels: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    private static func videoFrame(_ url: URL) async -> CGImage? {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: pixelSize, height: pixelSize)
        return try? await generator.image(at: CMTime(seconds: 0.1, preferredTimescale: 600)).image
    }
}

/// Lets only a few thumbnails be made at once.
actor Limiter {
    private var available: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(count: Int) { available = count }

    func acquire() async {
        if available > 0 {
            available -= 1
        } else {
            await withCheckedContinuation { waiters.append($0) }
        }
    }

    func release() {
        if waiters.isEmpty {
            available += 1
        } else {
            waiters.removeFirst().resume()
        }
    }
}
