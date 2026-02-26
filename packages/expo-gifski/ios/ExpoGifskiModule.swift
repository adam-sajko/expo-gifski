import AVFoundation
import ExpoModulesCore
import Foundation
import UIKit

private final class ExpoProgressCallbackImpl: GifskiProgressCallback, @unchecked Sendable {
    private weak var module: ExpoGifskiModule?

    init(module: ExpoGifskiModule) {
        self.module = module
    }

    func onProgress(progress: GifskiProgress) {
        guard let module = module else { return }
        DispatchQueue.main.async {
            module.sendEvent("onProgress", [
                "framesProcessed": progress.framesProcessed,
                "totalFrames": progress.totalFrames,
                "progress": progress.progress
            ])
        }
    }
}

public class ExpoGifskiModule: Module {
    public func definition() -> ModuleDefinition {
        Name("ExpoGifski")

        Events("onProgress")

        AsyncFunction("encodeGifFromVideo") { (videoUri: String, outputPath: String, options: [String: Any]?) -> String in
            return try self.encodeGifFromVideoImpl(videoUri: videoUri, outputPath: outputPath, options: options ?? [:])
        }

        Function("getModuleVersion") {
            return getModuleVersion()
        }

        Function("getGifskiVersion") {
            return getGifskiVersion()
        }

        AsyncFunction("getVideoThumbnail") { (videoUri: String, timeMs: Double) -> [String: Any] in
            return try self.getVideoThumbnailImpl(videoUri: videoUri, timeMs: timeMs)
        }
    }

    private func resolveFilePath(_ uriOrPath: String) -> String {
        if uriOrPath.hasPrefix("file://") {
            return URL(string: uriOrPath)?.path ?? uriOrPath
        }
        return uriOrPath
    }

    private func makeGifskiOptions(from options: [String: Any], width: Int, height: Int) -> GifskiOptions {
        let quality = (options["quality"] as? Int ?? 90)
        let repeat_ = options["repeat"] as? Int ?? -1
        return GifskiOptions(
            width: UInt32(clamping: max(width, 0)),
            height: UInt32(clamping: max(height, 0)),
            quality: UInt8(clamping: quality.clamped(to: 1...100)),
            repeat: Int32(clamping: repeat_),
            fast: options["fast"] as? Bool ?? false,
            fps: Float(options["fps"] as? Double ?? 10.0)
        )
    }

    private func computeTargetSize(from options: [String: Any], fallbackWidth: CGFloat, fallbackHeight: CGFloat) -> CGSize {
        let userWidth = options["width"] as? Int ?? 0
        let userHeight = options["height"] as? Int ?? 0

        if userWidth > 0 && userHeight > 0 {
            return CGSize(width: userWidth, height: userHeight)
        }

        let maxDim: CGFloat = 800
        if fallbackWidth > maxDim || fallbackHeight > maxDim {
            let scale = min(maxDim / fallbackWidth, maxDim / fallbackHeight)
            return CGSize(width: round(fallbackWidth * scale), height: round(fallbackHeight * scale))
        }
        return CGSize(width: fallbackWidth, height: fallbackHeight)
    }

    private func encodeGifFromVideoImpl(videoUri: String, outputPath: String, options: [String: Any]) throws -> String {
        let resolvedOutput = resolveFilePath(outputPath)
        let resolvedVideo = resolveFilePath(videoUri)

        let videoURL: URL
        if resolvedVideo.hasPrefix("/") {
            videoURL = URL(fileURLWithPath: resolvedVideo)
        } else if let url = URL(string: videoUri) {
            videoURL = url
        } else {
            throw NSError(domain: "ExpoGifski", code: -10, userInfo: [
                NSLocalizedDescriptionKey: "Invalid video URI: \(videoUri)"
            ])
        }

        let asset = AVURLAsset(url: videoURL)

        let assetDuration = CMTimeGetSeconds(asset.duration)
        guard assetDuration > 0 else {
            throw NSError(domain: "ExpoGifski", code: -11, userInfo: [
                NSLocalizedDescriptionKey: "Could not determine video duration or video is empty"
            ])
        }

        let fps = options["fps"] as? Double ?? 10.0
        let startTime = options["startTime"] as? Double ?? 0.0
        let requestedDuration = options["duration"] as? Double
        let duration = min(requestedDuration ?? (assetDuration - startTime), assetDuration - startTime)

        guard duration > 0 else {
            throw NSError(domain: "ExpoGifski", code: -12, userInfo: [
                NSLocalizedDescriptionKey: "Invalid time range: startTime=\(startTime) exceeds video duration=\(assetDuration)"
            ])
        }

        NSLog("[ExpoGifski] Video: duration=%.2fs, extracting from %.2fs for %.2fs at %.1f fps", assetDuration, startTime, duration, fps)

        let videoTrack = asset.tracks(withMediaType: .video).first
        let naturalSize = videoTrack?.naturalSize ?? CGSize(width: 480, height: 360)
        let targetSize = computeTargetSize(from: options, fallbackWidth: naturalSize.width, fallbackHeight: naturalSize.height)
        NSLog("[ExpoGifski] Target frame size: %.0fx%.0f", targetSize.width, targetSize.height)

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        generator.maximumSize = targetSize

        let frameInterval = 1.0 / fps
        let frameCount = Int((duration / frameInterval).rounded(.down))

        NSLog("[ExpoGifski] Extracting %d frames from video", frameCount)

        var tempPngPaths: [String] = []
        defer {
            for path in tempPngPaths {
                try? FileManager.default.removeItem(atPath: path)
            }
        }

        for index in 0..<frameCount {
            autoreleasepool {
                let timestamp = startTime + Double(index) * frameInterval
                let time = CMTime(seconds: timestamp, preferredTimescale: 600)
                do {
                    let cgImage = try generator.copyCGImage(at: time, actualTime: nil)
                    let image = UIImage(cgImage: cgImage)
                    guard let pngData = image.pngData() else {
                        NSLog("[ExpoGifski] Frame %d (t=%.3fs): skipping, could not convert to PNG", index, timestamp)
                        return
                    }
                    let tmpDir = NSTemporaryDirectory()
                    let filename = "expo_gifski_\(UUID().uuidString).png"
                    let tmpPath = (tmpDir as NSString).appendingPathComponent(filename)
                    try pngData.write(to: URL(fileURLWithPath: tmpPath))
                    tempPngPaths.append(tmpPath)
                } catch {
                    NSLog("[ExpoGifski] Frame %d (t=%.3fs): failed to extract - %@", index, timestamp, error.localizedDescription)
                }
            }
        }

        guard !tempPngPaths.isEmpty else {
            throw NSError(domain: "ExpoGifski", code: -6, userInfo: [
                NSLocalizedDescriptionKey: "Failed to extract any frames from video"
            ])
        }

        NSLog("[ExpoGifski] Extracted %d frames, encoding GIF...", tempPngPaths.count)

        let gifskiOptions = makeGifskiOptions(from: options, width: Int(targetSize.width), height: Int(targetSize.height))
        let progressCb = ExpoProgressCallbackImpl(module: self)

        do {
            try encodeGif(
                inputPaths: tempPngPaths,
                outputPath: resolvedOutput,
                options: gifskiOptions,
                progressCallback: progressCb
            )
        } catch let error as GifskiError {
            throw NSError(domain: "ExpoGifski", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "Failed to encode GIF from video: \(error)"
            ])
        } catch {
            throw NSError(domain: "ExpoGifski", code: -99, userInfo: [
                NSLocalizedDescriptionKey: "Unexpected error during GIF encoding: \(error.localizedDescription)"
            ])
        }

        return outputPath
    }

    private func getVideoThumbnailImpl(videoUri: String, timeMs: Double) throws -> [String: Any] {
        let resolvedVideo = resolveFilePath(videoUri)

        let videoURL: URL
        if resolvedVideo.hasPrefix("/") {
            videoURL = URL(fileURLWithPath: resolvedVideo)
        } else if let url = URL(string: videoUri) {
            videoURL = url
        } else {
            throw NSError(domain: "ExpoGifski", code: -10, userInfo: [
                NSLocalizedDescriptionKey: "Invalid video URI: \(videoUri)"
            ])
        }

        let asset = AVURLAsset(url: videoURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.1, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.1, preferredTimescale: 600)

        let time = CMTime(seconds: timeMs / 1000.0, preferredTimescale: 600)
        let cgImage = try generator.copyCGImage(at: time, actualTime: nil)
        let image = UIImage(cgImage: cgImage)

        guard let jpegData = image.jpegData(compressionQuality: 0.9) else {
            throw NSError(domain: "ExpoGifski", code: -20, userInfo: [
                NSLocalizedDescriptionKey: "Failed to encode thumbnail as JPEG"
            ])
        }

        let filename = "expo_gifski_thumb_\(UUID().uuidString).jpg"
        let tmpPath = (NSTemporaryDirectory() as NSString).appendingPathComponent(filename)
        let tmpURL = URL(fileURLWithPath: tmpPath)
        try jpegData.write(to: tmpURL)

        return [
            "uri": tmpURL.absoluteString,
            "width": cgImage.width,
            "height": cgImage.height
        ]
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        return min(max(self, range.lowerBound), range.upperBound)
    }
}
