import AVFoundation
import Foundation

/// Thin wrapper around `AVCaptureSession`.
///
/// It only produces frames; everything about filtering, recording and saving
/// lives above it. Frames arrive on `videoQueue`, which is where the whole
/// filter pipeline runs.
final class CameraSession: NSObject {
    let session = AVCaptureSession()
    let videoQueue = DispatchQueue(label: "com.snappy.video", qos: .userInitiated)
    private let configurationQueue = DispatchQueue(label: "com.snappy.session")

    private var videoInput: AVCaptureDeviceInput?
    private var audioInput: AVCaptureDeviceInput?
    private let videoOutput = AVCaptureVideoDataOutput()
    private let audioOutput = AVCaptureAudioDataOutput()
    private var isConfigured = false

    private(set) var position: AVCaptureDevice.Position = .front

    /// Called on `videoQueue` for every video frame.
    var onVideoFrame: ((CMSampleBuffer) -> Void)?
    /// Called on `videoQueue` for every audio sample, once audio is enabled.
    var onAudioSample: ((CMSampleBuffer) -> Void)?

    var isFrontCamera: Bool { position == .front }

    // MARK: - Lifecycle

    func configure(position: AVCaptureDevice.Position = .front) {
        configurationQueue.async { [weak self] in
            guard let self, !self.isConfigured else { return }
            self.session.beginConfiguration()
            self.session.sessionPreset = .hd1920x1080

            self.videoOutput.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
            self.videoOutput.alwaysDiscardsLateVideoFrames = true
            self.videoOutput.setSampleBufferDelegate(self, queue: self.videoQueue)
            if self.session.canAddOutput(self.videoOutput) {
                self.session.addOutput(self.videoOutput)
            }

            self.session.commitConfiguration()
            self.isConfigured = true
            self.attachCamera(at: position)
        }
    }

    func start() {
        configurationQueue.async { [weak self] in
            guard let self, !self.session.isRunning else { return }
            self.session.startRunning()
        }
    }

    func stop() {
        configurationQueue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
        }
    }

    // MARK: - Devices

    func flip() {
        attachCamera(at: position == .front ? .back : .front)
    }

    private func attachCamera(at position: AVCaptureDevice.Position) {
        configurationQueue.async { [weak self] in
            guard let self, let device = Self.device(for: position) else { return }
            self.session.beginConfiguration()
            defer {
                self.session.commitConfiguration()
                self.applyOrientation()
            }

            if let existing = self.videoInput {
                self.session.removeInput(existing)
            }
            guard let input = try? AVCaptureDeviceInput(device: device),
                  self.session.canAddInput(input) else { return }
            self.session.addInput(input)
            self.videoInput = input
            self.position = position
        }
    }

    private static func device(for position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        let types: [AVCaptureDevice.DeviceType] = position == .front
            ? [.builtInTrueDepthCamera, .builtInWideAngleCamera]
            : [.builtInDualWideCamera, .builtInDualCamera, .builtInWideAngleCamera]
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: types, mediaType: .video, position: position
        )
        return discovery.devices.first
    }

    /// The app is portrait-only, so the frames are rotated once here and every
    /// stage downstream (filters, Vision, recorder) works with an upright image.
    private func applyOrientation() {
        guard let connection = videoOutput.connection(with: .video) else { return }
        if connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }
        if connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = (position == .front)
        }
    }

    // MARK: - Audio

    /// Audio inputs are added the first time a recording starts, so the microphone
    /// permission prompt only appears when it is actually needed.
    func enableAudio() {
        configurationQueue.async { [weak self] in
            guard let self, self.audioInput == nil,
                  let device = AVCaptureDevice.default(for: .audio),
                  let input = try? AVCaptureDeviceInput(device: device) else { return }
            self.session.beginConfiguration()
            if self.session.canAddInput(input) {
                self.session.addInput(input)
                self.audioInput = input
            }
            self.audioOutput.setSampleBufferDelegate(self, queue: self.videoQueue)
            if self.session.canAddOutput(self.audioOutput) {
                self.session.addOutput(self.audioOutput)
            }
            self.session.commitConfiguration()
        }
    }

    // MARK: - Controls

    func setZoom(_ factor: CGFloat) {
        guard let device = videoInput?.device else { return }
        configurationQueue.async {
            guard (try? device.lockForConfiguration()) != nil else { return }
            let maximum = min(device.activeFormat.videoMaxZoomFactor, 8)
            device.videoZoomFactor = max(1, min(factor, maximum))
            device.unlockForConfiguration()
        }
    }

    var maximumZoom: CGFloat {
        min(videoInput?.device.activeFormat.videoMaxZoomFactor ?? 1, 8)
    }

    func setTorch(_ on: Bool) {
        guard let device = videoInput?.device, device.hasTorch else { return }
        configurationQueue.async {
            guard (try? device.lockForConfiguration()) != nil else { return }
            device.torchMode = on ? .on : .off
            device.unlockForConfiguration()
        }
    }

    var hasTorch: Bool { videoInput?.device.hasTorch ?? false }

    /// Tap-to-focus. `point` is in normalized (0...1) coordinates with the origin
    /// at the top-left of the preview.
    func focus(at point: CGPoint) {
        guard let device = videoInput?.device else { return }
        configurationQueue.async {
            guard (try? device.lockForConfiguration()) != nil else { return }
            if device.isFocusPointOfInterestSupported {
                device.focusPointOfInterest = point
                device.focusMode = .autoFocus
            }
            if device.isExposurePointOfInterestSupported {
                device.exposurePointOfInterest = point
                device.exposureMode = .continuousAutoExposure
            }
            device.unlockForConfiguration()
        }
    }
}

extension CameraSession: AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        if output === videoOutput {
            onVideoFrame?(sampleBuffer)
        } else if output === audioOutput {
            onAudioSample?(sampleBuffer)
        }
    }
}
