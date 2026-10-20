import SwiftUI

@main
struct FilmCamApp: App {
    @StateObject private var manager = CameraManager()

    var body: some Scene {
        WindowGroup {
            CameraRoot()
                .environmentObject(manager)
                .statusBarHidden()
        }
    }
}
