import SwiftUI

struct CameraScreen: View {
    @EnvironmentObject private var camera: CameraViewModel
    let onOpenGallery: () -> Void
    let onOpenSettings: () -> Void

    @State private var focusIndicator: CGPoint?
    @State private var shutterFlash = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch camera.permission {
            case .granted:
                viewfinder
            case .denied:
                PermissionDeniedView()
            case .unknown:
                ProgressView().tint(.white)
            }

            controls
        }
        .task { await camera.prepare() }
        .onDisappear { camera.stop() }
    }

    // MARK: - Viewfinder

    private var viewfinder: some View {
        GeometryReader { geometry in
            CameraPreview(view: camera.previewView)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 40)
                        .onEnded { value in
                            guard abs(value.translation.width) > abs(value.translation.height) else { return }
                            if value.translation.width < 0 {
                                camera.selectNext()
                            } else {
                                camera.selectPrevious()
                            }
                        }
                )
                .simultaneousGesture(
                    MagnificationGesture()
                        .onChanged { camera.updateZoom(scale: $0) }
                        .onEnded { _ in camera.beginZoomGesture() }
                )
                .onTapGesture(coordinateSpace: .local) { location in
                    let normalized = CGPoint(x: location.y / geometry.size.height,
                                             y: 1 - location.x / geometry.size.width)
                    camera.focus(atNormalizedPoint: normalized)
                    focusIndicator = location
                    Task {
                        try? await Task.sleep(for: .milliseconds(700))
                        focusIndicator = nil
                    }
                }
                .overlay(alignment: .topLeading) {
                    if let focusIndicator {
                        FocusReticle()
                            .position(focusIndicator)
                            .transition(.opacity)
                    }
                }
                .overlay {
                    Color.white
                        .opacity(shutterFlash ? 0.85 : 0)
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                }
        }
    }

    // MARK: - Controls

    private var controls: some View {
        VStack {
            topBar
            if let message = camera.statusMessage {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(.black.opacity(0.55), in: Capsule())
                    .padding(.top, 10)
                    .transition(.opacity)
            }
            Spacer()
            if camera.permission == .granted {
                bottomBar
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
    }

    private var topBar: some View {
        HStack(spacing: 18) {
            if camera.isRecording {
                RecordingBadge(seconds: camera.recordingSeconds)
            }
            Spacer()
            if camera.hasTorch {
                CircleButton(symbol: camera.torchOn ? "bolt.fill" : "bolt.slash",
                             action: camera.toggleTorch)
            }
            CircleButton(symbol: "arrow.triangle.2.circlepath.camera", action: camera.flipCamera)
            CircleButton(symbol: "gearshape", action: onOpenSettings)
        }
        .padding(.top, 8)
    }

    private var bottomBar: some View {
        VStack(spacing: 18) {
            FilterCarousel(effects: camera.effects, selectedIndex: $camera.selectedIndex)

            HStack {
                GalleryButton(capture: camera.store.latest, action: onOpenGallery)
                    .environmentObject(camera.store)
                Spacer()
                ShutterButton(
                    isRecording: camera.isRecording,
                    onPhoto: {
                        camera.capturePhoto()
                        withAnimation(.easeOut(duration: 0.08)) { shutterFlash = true }
                        withAnimation(.easeIn(duration: 0.18).delay(0.08)) { shutterFlash = false }
                    },
                    onStartRecording: { Task { await camera.startRecording() } },
                    onStopRecording: { Task { await camera.stopRecording() } }
                )
                Spacer()
                // Balances the shutter; long-press hint lives here.
                Text("Hold to\nrecord")
                    .font(.caption2)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(width: 58)
            }
        }
    }
}

// MARK: - Pieces

private struct FocusReticle: View {
    @State private var scale: CGFloat = 1.4

    var body: some View {
        RoundedRectangle(cornerRadius: 6)
            .stroke(Color.yellow, lineWidth: 1.5)
            .frame(width: 74, height: 74)
            .scaleEffect(scale)
            .onAppear {
                withAnimation(.easeOut(duration: 0.25)) { scale = 1 }
            }
    }
}

private struct RecordingBadge: View {
    let seconds: TimeInterval

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(.red).frame(width: 8, height: 8)
            Text(String(format: "%02d:%02d", Int(seconds) / 60, Int(seconds) % 60))
                .font(.system(.footnote, design: .monospaced))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.black.opacity(0.45), in: Capsule())
    }
}

private struct CircleButton: View {
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(.black.opacity(0.35), in: Circle())
        }
        .buttonStyle(.plain)
    }
}

private struct ShutterButton: View {
    let isRecording: Bool
    let onPhoto: () -> Void
    let onStartRecording: () -> Void
    let onStopRecording: () -> Void

    @GestureState private var isPressing = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(.white, lineWidth: 4)
                .frame(width: 76, height: 76)
            Circle()
                .fill(isRecording ? Color.red : Color.white)
                .frame(width: isRecording ? 34 : 62, height: isRecording ? 34 : 62)
                .animation(.spring(duration: 0.25), value: isRecording)
        }
        .contentShape(Circle())
        .onTapGesture {
            guard !isRecording else { return }
            onPhoto()
        }
        .gesture(
            LongPressGesture(minimumDuration: 0.35)
                .updating($isPressing) { value, state, _ in state = value }
                .onEnded { _ in onStartRecording() }
                .sequenced(before: DragGesture(minimumDistance: 0)
                    .onEnded { _ in onStopRecording() })
        )
        .accessibilityLabel(isRecording ? "Stop recording" : "Take photo")
        .accessibilityHint("Tap for a photo, hold to record video")
    }
}

private struct GalleryButton: View {
    let capture: Capture?
    let action: () -> Void
    @EnvironmentObject private var store: CaptureStore
    @State private var thumbnail: UIImage?

    var body: some View {
        Button(action: action) {
            Group {
                if let thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "photo.on.rectangle")
                        .font(.system(size: 18))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 52, height: 52)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.5), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .task(id: capture?.id) {
            guard let capture else { thumbnail = nil; return }
            thumbnail = await store.thumbnail(for: capture)
        }
    }
}

private struct PermissionDeniedView: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "camera.metering.unknown")
                .font(.system(size: 44))
            Text("Snappy needs the camera")
                .font(.headline)
            Text("Turn the camera on for Snappy in Settings and come back.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Open Settings") {
                guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                UIApplication.shared.open(url)
            }
            .buttonStyle(.borderedProminent)
        }
        .foregroundStyle(.white)
        .padding(40)
    }
}
