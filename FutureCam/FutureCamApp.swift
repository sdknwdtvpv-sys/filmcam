import SwiftUI

@main
struct FutureCamApp: App {
    @StateObject private var manager = CameraManager()
    @StateObject private var language = LanguageStore.shared

    var body: some Scene {
        WindowGroup {
            CameraRoot()
                .environmentObject(manager)
                .environmentObject(language)
                .statusBarHidden()
        }
    }
}
