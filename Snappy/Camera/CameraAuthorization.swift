import AVFoundation

enum CameraAuthorization {
    enum Status {
        case authorized
        case denied
        case undetermined
    }

    static var camera: Status {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return .authorized
        case .notDetermined: return .undetermined
        default: return .denied
        }
    }

    static func requestCamera() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .video)
    }

    /// Only asked for the first time the user hits record, so the mic prompt does
    /// not appear at launch.
    static func requestMicrophone() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }

    static var microphoneAuthorized: Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }
}
