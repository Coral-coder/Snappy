import AVFoundation
import ImageIO
import Photos
import SwiftUI
import UniformTypeIdentifiers

struct Capture: Identifiable, Hashable {
    enum Kind: String {
        case photo
        case video
    }

    let id: String
    let url: URL
    let kind: Kind
    let date: Date

    var isVideo: Bool { kind == .video }
}

/// Everything Snappy shoots lands in the app's own container first, not the
/// system photo library. Saving to Photos or sharing is always an explicit choice.
@MainActor
final class CaptureStore: ObservableObject {
    @Published private(set) var captures: [Capture] = []

    private let directory: URL
    private let thumbnails = NSCache<NSString, UIImage>()

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        directory = support.appendingPathComponent("Captures", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        reload()
    }

    // MARK: - Reading

    func reload() {
        let keys: [URLResourceKey] = [.contentModificationDateKey]
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]
        )) ?? []

        captures = contents.compactMap { url -> Capture? in
            let kind: Capture.Kind
            switch url.pathExtension.lowercased() {
            case "jpg", "jpeg", "heic": kind = .photo
            case "mp4", "mov": kind = .video
            default: return nil
            }
            let date = (try? url.resourceValues(forKeys: Set(keys)))?.contentModificationDate ?? .distantPast
            return Capture(id: url.lastPathComponent, url: url, kind: kind, date: date)
        }
        .sorted { $0.date > $1.date }
    }

    var latest: Capture? { captures.first }

    // MARK: - Writing

    /// Moves a finished recording out of the temporary directory into the library.
    @discardableResult
    func adoptVideo(at temporaryURL: URL) -> Capture? {
        let destination = directory.appendingPathComponent("\(Self.timestamp()).mp4")
        do {
            try FileManager.default.moveItem(at: temporaryURL, to: destination)
        } catch {
            return nil
        }
        reload()
        return captures.first { $0.url == destination }
    }

    @discardableResult
    func saveJPEG(_ data: Data) -> Capture? {
        let destination = directory.appendingPathComponent("\(Self.timestamp()).jpg")
        guard (try? data.write(to: destination, options: .atomic)) != nil else { return nil }
        reload()
        return captures.first { $0.url == destination }
    }

    func delete(_ capture: Capture) {
        try? FileManager.default.removeItem(at: capture.url)
        thumbnails.removeObject(forKey: capture.id as NSString)
        reload()
    }

    // MARK: - Photos library

    enum SaveResult {
        case saved
        case denied
        case failed
    }

    /// Copies a capture into the system photo library, asking for add-only access.
    func saveToPhotoLibrary(_ capture: Capture) async -> SaveResult {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { return .denied }

        do {
            try await PHPhotoLibrary.shared().performChanges {
                let request: PHAssetChangeRequest?
                if capture.isVideo {
                    request = PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: capture.url)
                } else {
                    request = PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: capture.url)
                }
                _ = request
            }
            return .saved
        } catch {
            return .failed
        }
    }

    // MARK: - Thumbnails

    func thumbnail(for capture: Capture, size: CGFloat = 240) async -> UIImage? {
        if let cached = thumbnails.object(forKey: capture.id as NSString) { return cached }

        let url = capture.url
        let isVideo = capture.isVideo
        let image: UIImage? = await Task.detached(priority: .userInitiated) {
            isVideo ? Self.videoThumbnail(url: url, size: size) : Self.imageThumbnail(url: url, size: size)
        }.value

        if let image { thumbnails.setObject(image, forKey: capture.id as NSString) }
        return image
    }

    private nonisolated static func imageThumbnail(url: URL, size: CGFloat) -> UIImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            // 3x covers every current iPhone; reading UIScreen here would mean
            // hopping to the main actor for a background thumbnail.
            kCGImageSourceThumbnailMaxPixelSize: size * 3
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    private nonisolated static func videoThumbnail(url: URL, size: CGFloat) -> UIImage? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: size * 2, height: size * 2)
        guard let cgImage = try? generator.copyCGImage(at: CMTime(value: 0, timescale: 60), actualTime: nil) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"
        return formatter.string(from: Date())
    }
}
