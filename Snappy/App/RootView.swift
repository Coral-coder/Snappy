import SwiftUI

/// Snappy has exactly three screens: the camera, the roll of things you shot,
/// and a short settings list. There is no feed, no profile and no login.
struct RootView: View {
    @EnvironmentObject private var camera: CameraViewModel
    @State private var route: Route?

    enum Route: Hashable {
        case gallery
        case settings
    }

    var body: some View {
        CameraScreen(onOpenGallery: { route = .gallery },
                     onOpenSettings: { route = .settings })
            .fullScreenCover(item: $route) { destination in
                switch destination {
                case .gallery:
                    GalleryScreen(onClose: { route = nil })
                case .settings:
                    SettingsScreen(onClose: { route = nil })
                }
            }
            .onChange(of: route) { _, newValue in
                // The capture session is the most expensive thing in the app, so it
                // only runs while the viewfinder is actually on screen.
                if newValue == nil {
                    camera.start()
                } else {
                    camera.stop()
                }
            }
    }
}

extension RootView.Route: Identifiable {
    var id: Self { self }
}
