import SwiftUI

@main
struct FutureCamApp: App {
    @StateObject private var manager = CameraManager()

    var body: some Scene {
        WindowGroup {
            CameraRoot()
                .environmentObject(manager)
                .statusBarHidden()
        }
    }
}
