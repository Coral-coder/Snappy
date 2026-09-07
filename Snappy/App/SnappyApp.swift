import SwiftUI

@main
struct SnappyApp: App {
    @StateObject private var camera = CameraViewModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(camera)
                .preferredColorScheme(.dark)
                .statusBarHidden()
        }
    }
}
