import AVFoundation

/// 音频会话由 App 自己持有，不交给采集会话自动配置。
///
/// 一旦让 AVFoundation 自动配置，它会把类别锁成 `.playAndRecord` ——
/// 那个类别**不跟随静音键**，齿轮声在静音时照样响，而且从 App 侧改不回 `.ambient`
///（实测报 `'!pri'` insufficient priority）。
///
/// 所以：预览阶段用 `.ambient`（跟随静音键，可与其他 App 混音），
/// 只有真正录像时才切到 `.playAndRecord` 让麦克风工作。
enum AudioRoute {
    static func idle() {
        apply(.ambient, mode: .default, options: [.mixWithOthers])
    }

    static func capture() {
        apply(.playAndRecord, mode: .videoRecording,
              options: [.defaultToSpeaker, .allowBluetoothA2DP])
    }

    private static func apply(_ category: AVAudioSession.Category,
                              mode: AVAudioSession.Mode,
                              options: AVAudioSession.CategoryOptions) {
        let session = AVAudioSession.sharedInstance()
        guard session.category != category || session.mode != mode else { return }
        do {
            try session.setCategory(category, mode: mode, options: options)
            try session.setActive(true)
        } catch {
            NSLog("[FutureCam] 音频会话切到 \(category.rawValue) 失败：\(error)")
        }
    }
}
