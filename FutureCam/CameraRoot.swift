import SwiftUI

/// 应用根视图：装配「测距仪」机身，并承载所有共享浮层
/// （权限引导、显影、提示条、胶片/设置弹层、相册）。
struct CameraRoot: View {
    @EnvironmentObject var manager: CameraManager
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            RangefinderCameraView()

            // 权限引导（可操作，绝不空转/死锁）
            if manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted {
                PermissionGate(
                    title: "相机权限已关闭",
                    message: "FutureCam 需要相机权限才能拍摄。点下方按钮前往系统设置开启相机权限，然后返回本页即可。",
                    buttonTitle: "去系统设置开启",
                    action: { manager.openSystemSettings() })
            } else if manager.authorizationStatus == .notDetermined {
                PermissionGate(
                    title: "需要相机权限",
                    message: "FutureCam 需要访问相机来拍摄复古胶片照片。",
                    buttonTitle: "授权并开启",
                    action: { manager.requestAccessAndConfigure() })
            }

            // 成片：撕拉片，往下拉出片
            if let captured = manager.capturedImage {
                #if DEBUG
                DevelopingPhotoView(image: captured,
                                    initialPull: DebugHarness.pullArgument ?? 0) {
                    manager.clearCaptured()
                }
                #else
                DevelopingPhotoView(image: captured) { manager.clearCaptured() }
                #endif
            }

            // 保存提示
            if manager.showVideoSaved { ToastVideoSaved() }
            if manager.videoSaveBlocked { ToastVideoBlocked() }
            if manager.photoSaveBlocked { ToastPhotoBlocked() }
            if manager.showDoubleExposureFirst { ToastDoubleExposureFirst() }

            // 弹层
            if manager.showFilmSheet { FilmSheet() }
            if manager.showSettingsSheet { SettingsSheet() }
            if manager.showAlbum { AlbumView() }
        }
        .animation(.easeInOut(duration: 0.22), value: manager.showFilmSheet)
        .animation(.easeInOut(duration: 0.22), value: manager.showSettingsSheet)
        .animation(.easeInOut(duration: 0.18), value: manager.activeParam)
        .sheet(isPresented: $manager.showVideoShare) {
            if let url = manager.recordedVideoURL {
                ShareSheet(items: [url])
            }
        }
        .onAppear {
            #if DEBUG
            DebugHarness.applyLaunchState(manager)
            if DebugHarness.shouldStubPreview { manager.enableStubPreview() }
            if DebugHarness.shouldTestEXIF { DebugHarness.writeEXIFSample() }
            if DebugHarness.shouldShowDeveloping {
                // 截图检查撕拉片时不要弹相机权限
                manager.capturedImage = DebugHarness.stubPreviewFrame()
            } else {
                manager.requestAccessAndConfigure()
            }
            #else
            manager.requestAccessAndConfigure()
            #endif
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                manager.refreshAuthorization()
            case .background:
                manager.pauseCamera()
            default:
                break
            }
        }
    }
}
