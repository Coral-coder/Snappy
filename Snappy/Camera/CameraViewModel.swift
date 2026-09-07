import AVFoundation
import CoreImage
import SwiftUI

/// Owns the capture session, the pipeline and the UI state for the camera screen.
@MainActor
final class CameraViewModel: ObservableObject {
    enum Permission {
        case unknown
        case granted
        case denied
    }

    @Published private(set) var permission: Permission = .unknown
    @Published private(set) var isRecording = false
    @Published private(set) var recordingSeconds: TimeInterval = 0
    @Published private(set) var isFrontCamera = true
    @Published var torchOn = false
    @Published var selectedIndex = 0 {
        didSet { applySelection() }
    }
    /// Set when a capture finishes, so the UI can flash a preview thumbnail.
    @Published var lastCapture: Capture?
    @Published private(set) var statusMessage: String?

    let catalog = FilterCatalog()
    let previewView = MetalPreviewView()
    let store = CaptureStore()

    private let session = CameraSession()
    private let pipeline = FramePipeline()
    private var recordingTimer: Timer?
    private var zoomBase: CGFloat = 1

    var effects: [LensEffect] { catalog.effects }
    var selectedEffect: LensEffect { catalog.effect(at: selectedIndex) }
    var hasTorch: Bool { session.hasTorch }

    init() {
        // The frame callbacks run on the video queue, so they capture the pipeline
        // and the view directly rather than reaching back through `self` (which is
        // main-actor bound). Nothing on this path touches published state.
        let pipeline = self.pipeline
        let preview = self.previewView

        session.onVideoFrame = { sampleBuffer in
            guard let filtered = pipeline.process(sampleBuffer) else { return }
            preview.present(filtered)
        }
        session.onAudioSample = { sampleBuffer in
            pipeline.recorder.append(audio: sampleBuffer)
        }
    }

    // MARK: - Lifecycle

    func prepare() async {
        switch CameraAuthorization.camera {
        case .authorized:
            permission = .granted
        case .undetermined:
            permission = await CameraAuthorization.requestCamera() ? .granted : .denied
        case .denied:
            permission = .denied
        }

        guard permission == .granted else { return }
        session.configure(position: .front)
        applySelection()
        session.start()
    }

    func start() {
        guard permission == .granted else { return }
        session.start()
    }

    func stop() {
        if isRecording { Task { await stopRecording() } }
        session.stop()
    }

    // MARK: - Filters

    private func applySelection() {
        let effect = catalog.effect(at: selectedIndex)
        session.videoQueue.async { [pipeline] in
            pipeline.effect = effect
        }
    }

    func selectNext() {
        selectedIndex = min(selectedIndex + 1, catalog.count - 1)
    }

    func selectPrevious() {
        selectedIndex = max(selectedIndex - 1, 0)
    }

    // MARK: - Camera controls

    func flipCamera() {
        session.flip()
        isFrontCamera = session.isFrontCamera
        session.videoQueue.async { [pipeline, isFrontCamera] in
            pipeline.isFrontCamera = isFrontCamera
        }
        if torchOn {
            torchOn = false
            session.setTorch(false)
        }
    }

    func toggleTorch() {
        torchOn.toggle()
        session.setTorch(torchOn)
    }

    func focus(atNormalizedPoint point: CGPoint) {
        session.focus(at: point)
    }

    func beginZoomGesture() {
        zoomBase = currentZoom
    }

    func updateZoom(scale: CGFloat) {
        currentZoom = max(1, min(zoomBase * scale, session.maximumZoom))
        session.setZoom(currentZoom)
    }

    private(set) var currentZoom: CGFloat = 1

    // MARK: - Capture

    /// Grabs the next filtered frame. Capturing the frame the user is already
    /// looking at is what makes the photo match the preview exactly.
    func capturePhoto() {
        session.videoQueue.async { [weak self, pipeline] in
            pipeline.pendingPhoto = { image in
                guard let data = pipeline.encodeJPEG(image) else { return }
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.lastCapture = self.store.saveJPEG(data)
                }
            }
        }
    }

    func startRecording() async {
        guard !isRecording else { return }

        if !CameraAuthorization.microphoneAuthorized {
            _ = await CameraAuthorization.requestMicrophone()
        }
        let withAudio = CameraAuthorization.microphoneAuthorized
        if withAudio { session.enableAudio() }

        // 1080p portrait: the pipeline hands the recorder upright frames.
        let size = CGSize(width: 1080, height: 1920)
        session.videoQueue.async { [pipeline] in
            try? pipeline.recorder.start(size: size, includeAudio: withAudio)
        }

        isRecording = true
        recordingSeconds = 0
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isRecording else { return }
                self.recordingSeconds += 0.1
                // Snappy caps clips at 60s; longer belongs in a real video app.
                if self.recordingSeconds >= 60 { await self.stopRecording() }
            }
        }
    }

    func stopRecording() async {
        guard isRecording else { return }
        isRecording = false
        recordingTimer?.invalidate()
        recordingTimer = nil

        let url = await pipeline.recorder.finish()
        guard let url else {
            flash("Nothing was recorded")
            return
        }
        lastCapture = store.adoptVideo(at: url)
    }

    /// Brief message over the viewfinder. The only feedback channel the camera
    /// screen has, so it is deliberately short-lived.
    private func flash(_ message: String) {
        statusMessage = message
        Task {
            try? await Task.sleep(for: .seconds(2))
            if statusMessage == message { statusMessage = nil }
        }
    }
}
