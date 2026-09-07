import SwiftUI

struct SettingsScreen: View {
    @EnvironmentObject private var camera: CameraViewModel
    let onClose: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section("What Snappy is") {
                    Label("No account, no feed, no ads", systemImage: "hand.raised")
                    Label("No analytics and no network calls", systemImage: "wifi.slash")
                    Label("Shots stay on device until you share them", systemImage: "iphone")
                }

                Section("Lenses") {
                    ForEach(catalogSummary, id: \.name) { row in
                        HStack {
                            Text(row.name)
                            Spacer()
                            Text("\(row.count)")
                                .foregroundStyle(.secondary)
                        }
                    }
                    if !SnapCameraKitProvider.isAvailable {
                        Text("Snap Camera Kit is not linked in this build. See docs/CAMERA_KIT.md to add real Snapchat Lenses.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("About") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text(Self.version).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done", action: onClose)
                }
            }
        }
    }

    private var catalogSummary: [(name: String, count: Int)] {
        camera.catalog.sections.map { (name: $0.provider, count: $0.range.count) }
    }

    private static var version: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
        return "\(short) (\(build))"
    }
}
