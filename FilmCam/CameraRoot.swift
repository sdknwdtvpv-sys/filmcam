import SwiftUI

/// 应用根视图：按当前主题装配相机界面，并承载所有共享浮层
/// （权限引导、显影、提示条、胶片/设置弹层、相册）。
struct CameraRoot: View {
    @EnvironmentObject var manager: CameraManager
    @Environment(\.scenePhase) private var scenePhase

    @AppStorage("filmcam.theme") private var themeRaw = ThemeID.precision.rawValue

    private var themeID: ThemeID { ThemeID(rawValue: themeRaw) ?? .precision }

    var body: some View {
        // 共享页面（相册 / 弹层 / 提示条）读的是 CameraTheme 静态令牌，
        // 所以在构建子树之前就要把当前主题写进去。
        ThemeStore.current = themeID.tokens

        return ZStack {
            themeScreen
                .transition(.opacity)

            // 权限引导（可操作，绝不空转/死锁）
            if manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted {
                PermissionGate(
                    title: "相机权限已关闭",
                    message: "FilmCam 需要相机权限才能拍摄。点下方按钮前往系统设置开启相机权限，然后返回本页即可。",
                    buttonTitle: "去系统设置开启",
                    action: { manager.openSystemSettings() })
            } else if manager.authorizationStatus == .notDetermined {
                PermissionGate(
                    title: "需要相机权限",
                    message: "FilmCam 需要访问相机来拍摄复古胶片照片。",
                    buttonTitle: "授权并开启",
                    action: { manager.requestAccessAndConfigure() })
            }

            // 成片：拍立得摇一摇显影
            if let captured = manager.capturedImage {
                DevelopingPhotoView(image: captured) { manager.clearCaptured() }
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

            // 主题切换入口（弹层 / 相册打开时收起，避免叠在内容上）
            if !manager.showAlbum && !manager.showFilmSheet && !manager.showSettingsSheet {
                VStack {
                    HStack {
                        ThemeSwitcher(selection: Binding(
                            get: { themeID },
                            set: { themeRaw = $0.rawValue }))
                        Spacer(minLength: 0)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.leading, 16)
                .padding(.top, 6)
                .ignoresSafeArea(edges: .top)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: themeRaw)
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
            if let forced = DebugHarness.themeArgument() {
                themeRaw = forced
            }
            DebugHarness.applyLaunchState(manager)
            if DebugHarness.shouldStubPreview { manager.enableStubPreview() }
            #endif
            manager.requestAccessAndConfigure()
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

    @ViewBuilder private var themeScreen: some View {
        switch themeID {
        case .precision: PrecisionCameraView()
        case .cockpit:   CockpitCameraView()
        case .rig:       RigCameraView()
        }
    }
}
