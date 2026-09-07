import AVKit
import SwiftUI

/// Everything shot with Snappy, stored in the app's own container. Nothing here
/// has been uploaded anywhere; saving to Photos and sharing are both explicit.
struct GalleryScreen: View {
    @EnvironmentObject private var camera: CameraViewModel
    let onClose: () -> Void

    @State private var selected: Capture?

    private let columns = [GridItem(.adaptive(minimum: 108), spacing: 3)]

    var body: some View {
        NavigationStack {
            Group {
                if camera.store.captures.isEmpty {
                    ContentUnavailableView(
                        "Nothing yet",
                        systemImage: "camera",
                        description: Text("Photos and videos you take show up here.")
                    )
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 3) {
                            ForEach(camera.store.captures) { capture in
                                Button { selected = capture } label: {
                                    CaptureThumbnail(capture: capture)
                                        .environmentObject(camera.store)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(3)
                    }
                }
            }
            .navigationTitle("Your shots")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done", action: onClose)
                }
            }
        }
        .fullScreenCover(item: $selected) { capture in
            CaptureDetailScreen(capture: capture, onClose: { selected = nil })
                .environmentObject(camera.store)
        }
        .onAppear { camera.store.reload() }
    }
}

struct CaptureThumbnail: View {
    let capture: Capture
    @EnvironmentObject private var store: CaptureStore
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Color.black.opacity(0.2)
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            }
            if capture.isVideo {
                Image(systemName: "play.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.9))
                    .shadow(radius: 3)
            }
        }
        .frame(height: 108)
        .clipped()
        .task {
            image = await store.thumbnail(for: capture)
        }
    }
}

/// One capture, full screen, with the three things you can do with it.
struct CaptureDetailScreen: View {
    let capture: Capture
    let onClose: () -> Void

    @EnvironmentObject private var store: CaptureStore
    @State private var isSharing = false
    @State private var message: String?
    @State private var confirmDelete = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if capture.isVideo {
                VideoPlayer(player: AVPlayer(url: capture.url))
                    .ignoresSafeArea()
            } else if let image = UIImage(contentsOfFile: capture.url.path) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .ignoresSafeArea()
            }

            VStack {
                HStack {
                    Button { onClose() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 38, height: 38)
                            .background(.black.opacity(0.4), in: Circle())
                    }
                    Spacer()
                }
                Spacer()

                if let message {
                    Text(message)
                        .font(.footnote)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.black.opacity(0.6), in: Capsule())
                        .foregroundStyle(.white)
                        .padding(.bottom, 8)
                }

                HStack(spacing: 30) {
                    ActionButton(symbol: "square.and.arrow.up", title: "Share") { isSharing = true }
                    ActionButton(symbol: "square.and.arrow.down", title: "Save") {
                        Task { await save() }
                    }
                    ActionButton(symbol: "trash", title: "Delete", tint: .red) { confirmDelete = true }
                }
                .padding(.bottom, 24)
            }
            .padding(.horizontal, 20)
        }
        .sheet(isPresented: $isSharing) {
            ShareSheet(items: [capture.url])
        }
        .confirmationDialog("Delete this?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                store.delete(capture)
                onClose()
            }
            Button("Keep", role: .cancel) {}
        }
    }

    private func save() async {
        switch await store.saveToPhotoLibrary(capture) {
        case .saved: message = "Saved to Photos"
        case .denied: message = "Photos access is off in Settings"
        case .failed: message = "Could not save"
        }
        try? await Task.sleep(for: .seconds(2))
        message = nil
    }
}

private struct ActionButton: View {
    let symbol: String
    let title: String
    var tint: Color = .white
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 20, weight: .medium))
                Text(title).font(.caption2)
            }
            .foregroundStyle(tint)
            .frame(width: 64, height: 58)
            .background(.black.opacity(0.4), in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }
}
