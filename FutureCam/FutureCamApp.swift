import SwiftUI

@main
struct FutureCamApp: App {
    @StateObject private var manager = CameraManager()
    @StateObject private var language = LanguageStore.shared

    init() {
        // 界面锁竖屏，但成片要按设备朝向转正——不开这个，orientation 永远是 unknown
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
    }

    var body: some Scene {
        WindowGroup {
            CameraRoot()
                .environmentObject(manager)
                .environmentObject(language)
                .statusBarHidden()
        }
    }
}
