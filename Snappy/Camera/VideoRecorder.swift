import AVFoundation
import CoreImage
import Foundation

/// Writes the *filtered* frames to an .mp4, so the recording matches the
/// viewfinder exactly. Audio sample buffers are passed through untouched.
final class VideoRecorder {
    enum RecorderError: Error {
        case couldNotCreateWriter
        case couldNotStart
    }

    private var writer: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?
    private var adaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var sessionStarted = false
    private var startTime: CMTime = .zero

    /// `isRecording` is read on the video queue and flipped from the main actor
    /// when a recording ends, so it is guarded.
    private let stateLock = NSLock()
    private var _isRecording = false
    var isRecording: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return _isRecording
    }
    private(set) var outputURL: URL?

    /// Wall-clock length of the recording so far, for the on-screen timer.
    var duration: CMTime {
        guard sessionStarted, let last = lastAppendedTime else { return .zero }
        return last - startTime
    }
    private var lastAppendedTime: CMTime?

    func start(size: CGSize, includeAudio: Bool) throws {
        guard !isRecording else { return }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("snappy-\(UUID().uuidString).mp4")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)

        let width = Int(size.width.rounded(.down) / 2) * 2
        let height = Int(size.height.rounded(.down) / 2) * 2

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: width * height * 6,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
            ]
        ]
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput.expectsMediaDataInRealTime = true

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height,
                kCVPixelBufferMetalCompatibilityKey as String: true
            ]
        )
        guard writer.canAdd(videoInput) else { throw RecorderError.couldNotCreateWriter }
        writer.add(videoInput)

        if includeAudio {
            let audioSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVNumberOfChannelsKey: 1,
                AVSampleRateKey: 44_100,
                AVEncoderBitRateKey: 96_000
            ]
            let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            audioInput.expectsMediaDataInRealTime = true
            if writer.canAdd(audioInput) {
                writer.add(audioInput)
                self.audioInput = audioInput
            }
        }

        guard writer.startWriting() else { throw RecorderError.couldNotStart }

        self.writer = writer
        self.videoInput = videoInput
        self.adaptor = adaptor
        self.outputURL = url
        self.sessionStarted = false
        stateLock.lock()
        _isRecording = true
        stateLock.unlock()
    }

    /// Called on the video queue for every filtered frame while recording.
    func append(image: CIImage, at time: CMTime, context: CIContext, colorSpace: CGColorSpace) {
        guard isRecording,
              let writer, writer.status == .writing,
              let videoInput, let adaptor,
              let pool = adaptor.pixelBufferPool else { return }

        if !sessionStarted {
            writer.startSession(atSourceTime: time)
            startTime = time
            sessionStarted = true
        }
        guard videoInput.isReadyForMoreMediaData else { return }

        var buffer: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &buffer) == kCVReturnSuccess,
              let pixelBuffer = buffer else { return }

        // The frame may be a different size than the writer (the writer is sized
        // from the first frame), so scale into the buffer's own rect.
        let target = CGRect(x: 0, y: 0,
                            width: CVPixelBufferGetWidth(pixelBuffer),
                            height: CVPixelBufferGetHeight(pixelBuffer))
        let fitted = MetalPreviewView.transform(image, toFill: target.size, fill: true)

        context.render(fitted,
                       to: pixelBuffer,
                       bounds: target,
                       colorSpace: colorSpace)
        adaptor.append(pixelBuffer, withPresentationTime: time)
        lastAppendedTime = time
    }

    func append(audio sampleBuffer: CMSampleBuffer) {
        guard isRecording, sessionStarted,
              let audioInput, audioInput.isReadyForMoreMediaData,
              writer?.status == .writing else { return }
        audioInput.append(sampleBuffer)
    }

    /// Finishes the file and hands back its URL, or nil if nothing was written.
    func finish() async -> URL? {
        stateLock.lock()
        let wasRecording = _isRecording
        // Flipping the flag first stops the video queue from appending into a
        // writer that is being torn down.
        _isRecording = false
        stateLock.unlock()
        guard wasRecording, let writer else { return nil }
        videoInput?.markAsFinished()
        audioInput?.markAsFinished()

        guard sessionStarted else {
            writer.cancelWriting()
            reset()
            return nil
        }

        await writer.finishWriting()
        let url = writer.status == .completed ? outputURL : nil
        reset()
        return url
    }

    private func reset() {
        writer = nil
        videoInput = nil
        audioInput = nil
        adaptor = nil
        sessionStarted = false
        lastAppendedTime = nil
    }
}
