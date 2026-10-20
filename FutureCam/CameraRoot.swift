import SwiftUI

/// 应用根视图：装配「测距仪」机身，并承载所有共享浮层
/// （权限引导、显影、提示条、胶片/设置弹层、相册）。
struct CameraRoot: View {
    @EnvironmentObject var manager: CameraManager
    @Environment(\.scenePhase) private var scenePhase
    /// 关键控件的屏幕位置：胶片仓从这里长出来，首跑引导也指这里
    @State private var anchors: [GuideTarget: CGRect] = [:]
    @AppStorage("futurecam.seenGuide.v2") private var seenGuide = false
    /// 冷启动时先放一次开机页
    @State private var showLaunch = true

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
            if manager.showFilmSheet { FilmSheet(anchor: anchors[.film] ?? .zero) }
            if manager.showSettingsSheet { SettingsSheet() }
            if manager.showAlbum { AlbumView() }

            // 冷启动的开机页，放完让位给取景器
            if showLaunch {
                LaunchScreenView(onFinish: {
                    withAnimation(.easeInOut(duration: 0.3)) { showLaunch = false }
                }, frozen: launchFrozen)
                .zIndex(20)
                .transition(.opacity)
            }

            // 一次性的用法引导（拍过一张或点一下就不再出现）
            if shouldShowGuide {
                FirstRunGuide(anchors: anchors,
                              onFinish: { seenGuide = true },
                              initialStep: guideInitialStep)
                    .transition(.opacity)
            }
        }
        .onPreferenceChange(GuideAnchorKey.self) { anchors = $0 }
        .animation(.spring(response: 0.32, dampingFraction: 0.82),
                   value: manager.showFilmSheet)
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
                DetentFeedback.shared.prepare()
                updateFeedbackSound()
            case .background:
                manager.pauseCamera()
                DetentFeedback.shared.suspend()
            default:
                break
            }
        }
        .onChange(of: manager.isRecording) { _, _ in updateFeedbackSound() }
        .onChange(of: manager.mode) { _, _ in updateFeedbackSound() }
    }

    /// 视频模式下麦克风占着音频会话，会话被锁进 playAndRecord，静音键就管不住了；
    /// 干脆视频模式只留触感。拍照模式走 .ambient，静音键自动生效。
    private var launchFrozen: Bool {
        #if DEBUG
        return DebugHarness.shouldHoldLaunch
        #else
        return false
        #endif
    }

    private var guideInitialStep: Int {
        #if DEBUG
        return DebugHarness.guideStep
        #else
        return 0
        #endif
    }

    private var shouldShowGuide: Bool {
        guard !seenGuide, manager.capturedImage == nil else { return false }
        #if DEBUG
        if DebugHarness.shouldShowGuide { return true }
        #endif
        return manager.hasPreview && manager.authorizationStatus == .authorized
    }

    private func updateFeedbackSound() {
        DetentFeedback.shared.soundEnabled = manager.mode != .video && !manager.isRecording
    }
}
