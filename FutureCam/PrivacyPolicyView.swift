import SwiftUI

/// 隐私政策：内置在 App 里，不依赖网页，样式和「我的」同一个底部面板。
/// 审核要求「能随时访问」，本地内容比外链更稳——不会因为网络或托管挂了打不开。
struct PrivacyPolicyView: View {
    let onBack: () -> Void

    private var isEnglish: Bool {
        switch LanguageStore.shared.language {
        case .english: return true
        case .chinese: return false
        case .system:
            return Locale.preferredLanguages.first?.hasPrefix("en") == true
        }
    }

    var body: some View {
        let t = ThemeStore.current
        VStack(spacing: 0) {
                header(t)
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        ForEach(Self.sections(isEnglish: isEnglish), id: \.title) { section in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 6) {
                                    Circle().fill(t.accent).frame(width: 4, height: 4)
                                    Text(section.title)
                                        .font(t.monoFont(13, .bold))
                                        .foregroundColor(CameraTheme.ink)
                                }
                                Text(section.body)
                                    .font(.system(size: 13))
                                    .lineSpacing(4)
                                    .foregroundColor(CameraTheme.inkDim)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 44)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func header(_ t: ThemeTokens) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                ScrewHead(size: 7)
                Silkscreen(text: "PRIVACY", color: CameraTheme.ink.opacity(0.55),
                           size: 7, tracking: 2)
                Spacer()
                Button(isEnglish ? "Back" : "返回") { onBack() }
                    .font(CameraTheme.mono(11, weight: .bold))
                    .foregroundColor(CameraTheme.amber)
                ScrewHead(size: 7)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            GrooveLine()
        }
    }

    // MARK: 正文

    struct Section { let title: String; let body: String }

    static let contactEmail = "elliotsmail28@gmail.com"

    static func sections(isEnglish: Bool) -> [Section] {
        isEnglish ? english : chinese
    }

    private static let chinese: [Section] = [
        Section(title: "一句话",
                body: "FutureCam 是一台相机，不是一项服务。它不联网、不收集你的任何信息，照片从拍到存，全程只在你自己的手机里。"),
        Section(title: "收集哪些数据",
                body: "没有。不收集个人数据，不要求注册账号，没有广告，不做跨 App 追踪，也没有接入任何第三方 SDK——只用 Apple 系统框架。"),
        Section(title: "联网",
                body: "App 内没有任何网络请求代码。取景、滤镜、冲印、相册全部在设备本地完成。"),
        Section(title: "相机",
                body: "用于取景与拍摄。画面只在设备内处理，不会上传。"),
        Section(title: "麦克风",
                body: "仅在你切换到视频模式录像时收音。拍照时不使用麦克风。"),
        Section(title: "相册",
                body: "只写入，不读取。App 会把拍好的照片和视频存进你的相册，但不会访问你已有的照片。"),
        Section(title: "数据存放位置",
                body: "成片存在两处：App 自己的存储区（用于按胶卷分组浏览）和你的系统相册。卷号、张数、语言等偏好存在系统本地的 UserDefaults 里。这些数据都只在这台设备上——因为没有服务器。"),
        Section(title: "如何删除",
                body: "删除 App 即删除 App 内的全部数据。已经存进系统相册的照片是你自己的文件，会保留，可在相册里自行删除。"),
        Section(title: "儿童",
                body: "不收集任何人的信息，包括儿童。App 不含广告、不含外链、不含账号。"),
        Section(title: "政策变更",
                body: "如果未来版本引入需要联网的功能，这份政策会先更新，并在 App 内明确告知。"),
        Section(title: "联系",
                body: contactEmail)
    ]

    private static let english: [Section] = [
        Section(title: "In one sentence",
                body: "FutureCam is a camera, not a service. It does not connect to the internet and does not collect any information about you. Your photos never leave your iPhone."),
        Section(title: "What we collect",
                body: "Nothing. No personal data, no account, no ads, no cross-app tracking, and no third-party SDKs — Apple system frameworks only."),
        Section(title: "Network",
                body: "There is no networking code in the app. Viewing, filtering, printing and the gallery all happen on-device."),
        Section(title: "Camera",
                body: "Used to compose and capture. Everything is processed on the device and never uploaded."),
        Section(title: "Microphone",
                body: "Used only while recording video. It is never used for stills."),
        Section(title: "Photos",
                body: "Write-only. The app saves your photos and videos to your library but never reads your existing photos."),
        Section(title: "Where data lives",
                body: "Finished photos are stored in the app's own container (for the roll-grouped gallery) and in your system photo library. Roll numbers and preferences live in local UserDefaults. All of it stays on this device — there is no server."),
        Section(title: "Deletion",
                body: "Deleting the app deletes everything stored inside it. Photos already saved to your library are your own files and remain until you delete them."),
        Section(title: "Children",
                body: "No information is collected from anyone, including children. The app has no ads, no external links and no accounts."),
        Section(title: "Changes",
                body: "If a future version ever needs network access, this policy will be updated first and the change will be disclosed in the app."),
        Section(title: "Contact",
                body: contactEmail)
    ]
}
