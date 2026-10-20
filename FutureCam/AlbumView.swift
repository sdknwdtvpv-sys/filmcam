import SwiftUI
import AVKit

/// 相册里统一使用的中文日期格式（与拍立得底部时间戳一致）
enum AlbumDateFormat {
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy.MM.dd HH:mm"
        return f
    }()

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy.MM.dd"
        return f
    }()

    static func short(_ date: Date) -> String { formatter.string(from: date) }
    static func day(_ date: Date) -> String { dayFormatter.string(from: date) }
}

/// 应用内相册：网格浏览 → 全屏查看（照片可缩放 / 视频可播放）→ 分享 / 删除。
/// 数据全部来自本地沙盒（AlbumStore），不依赖系统相册读权限。
struct AlbumView: View {
    @EnvironmentObject var manager: CameraManager

    @State private var detailItem: AlbumItem?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 3)

    var body: some View {
        ZStack {
            // 洗印台：深色蒙皮底 + 一层压暗，相纸浮在上面
            LeatherPanel().ignoresSafeArea()
            Color.black.opacity(0.35).ignoresSafeArea()

            VStack(spacing: 0) {
                header
                if manager.albumItems.isEmpty {
                    emptyState
                } else {
                    grid
                }
            }

            if let detailItem {
                AlbumDetailView(startItem: detailItem) {
                    self.detailItem = nil
                }
                .transition(.opacity)
                .zIndex(1)
            }
        }
        .onAppear { manager.loadAlbum() }
        .task {
            #if DEBUG
            switch DebugHarness.screenArgument() {
            case "albumDetail":
                // 等本地相册扫描完再自动打开最新一条，方便截图自检
                try? await Task.sleep(nanoseconds: 500_000_000)
                detailItem = manager.albumItems.first
            case "albumPhoto":
                try? await Task.sleep(nanoseconds: 500_000_000)
                detailItem = manager.albumItems.first { $0.kind == .photo }
            default:
                break
            }
            #endif
        }
    }

    private var header: some View {
        let t = ThemeStore.current
        return HStack(spacing: 8) {
            ScrewHead(size: 7)
            Silkscreen(text: "CONTACT SHEET", color: .black.opacity(0.55), size: 7, tracking: 2)
            Text(String(format: "%02d EXP", manager.albumItems.count))
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(.black.opacity(0.45))
            Spacer()
            Text("相册")
                .font(t.monoFont(11, .bold))
                .foregroundColor(.black.opacity(0.55))
            Button { manager.closeAlbum() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.black.opacity(0.6))
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("关闭相册")
            ScrewHead(size: 7)
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
        .background(AluminumFace(tokens: t))
        .overlay(alignment: .bottom) {
            Rectangle().fill(.black.opacity(0.45)).frame(height: 1)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 30, weight: .light))
                .foregroundColor(CameraTheme.inkDim)
            Text("还没有照片，先拍一张吧")
                .foregroundColor(CameraTheme.ink.opacity(0.7))
                .font(CameraTheme.mono(14))
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    /// 按卷分组的相册：一卷一段，像翻底片袋
    private var grid: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                ForEach(sections) { section in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Silkscreen(text: section.title, color: .white.opacity(0.62),
                                       size: 6.5, tracking: 1.8)
                            Rectangle().fill(.white.opacity(0.16)).frame(height: 1)
                            Text(section.countText)
                                .font(.system(size: 8, weight: .bold, design: .monospaced))
                                .foregroundColor(.white.opacity(0.4))
                        }
                        .padding(.horizontal, 12)

                        LazyVGrid(columns: columns, spacing: 10) {
                            ForEach(section.items) { item in
                                Button { detailItem = item } label: {
                                    MediaThumbnail(item: item, maxPixel: 420)
                                        .aspectRatio(0.7, contentMode: .fit)
                                        .clipShape(RoundedRectangle(cornerRadius: 2))
                                        .shadow(color: .black.opacity(0.55), radius: 4, y: 2)
                                        .overlay(alignment: .bottomTrailing) {
                                            // 洗印编号（这一卷里的第几张）
                                            Text(section.indexText(for: item))
                                                .font(.system(size: 6.5, weight: .bold, design: .monospaced))
                                                .foregroundColor(.white.opacity(0.8))
                                                .padding(.horizontal, 4).padding(.vertical, 1)
                                                .background(Capsule().fill(.black.opacity(0.6)))
                                                .padding(4)
                                        }
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("\(item.kind == .video ? "视频" : "照片")，\(AlbumDateFormat.short(item.createdAt))")
                            }
                        }
                        .padding(.horizontal, 12)
                    }
                }
            }
            .padding(.vertical, 12)
        }
    }

    private var sections: [AlbumSection] {
        var groups: [String: [AlbumItem]] = [:]
        for item in manager.albumItems {
            let key = item.rollID ?? ""
            groups[key, default: []].append(item)
        }

        return groups.map { key, items in
            let sorted = items.sorted { $0.createdAt > $1.createdAt }
            if key.isEmpty {
                return AlbumSection(id: "unsorted", title: "未归档", items: sorted,
                                    subtitle: nil, capacity: nil)
            }
            let roll = RollStore.shared.roll(id: key)
            return AlbumSection(id: key,
                                title: roll.map { "\($0.preset.label)" } ?? "未知胶卷",
                                items: sorted,
                                subtitle: roll?.numberText,
                                capacity: roll?.capacity)
        }
        .sorted { lhs, rhs in
            if lhs.id == "unsorted" { return false }
            if rhs.id == "unsorted" { return true }
            return (lhs.items.first?.createdAt ?? .distantPast) > (rhs.items.first?.createdAt ?? .distantPast)
        }
    }
}

/// 相册里的一段：一卷胶卷（或未归档）
private struct AlbumSection: Identifiable {
    let id: String
    let title: String
    let items: [AlbumItem]
    let subtitle: String?
    let capacity: Int?

    /// 「第 3 卷 · 12 张」
    var countText: String {
        var parts: [String] = []
        if let subtitle { parts.append(subtitle) }
        parts.append(capacity.map { "\(items.count)/\($0) 张" } ?? "\(items.count) 张")
        return parts.joined(separator: " · ")
    }

    /// 这一卷里从 1 开始的序号（最新一张是最大号）
    func indexText(for item: AlbumItem) -> String {
        guard let index = items.firstIndex(of: item) else { return "--" }
        return String(format: "%02d", items.count - index)
    }
}

/// 全屏查看：照片支持双指缩放，视频用系统播放器控件。
struct AlbumDetailView: View {
    @EnvironmentObject var manager: CameraManager

    private let onClose: () -> Void

    @State private var item: AlbumItem
    @State private var image: UIImage?
    @State private var player: AVPlayer?
    @State private var isLoading = true
    @State private var showShare = false
    @State private var confirmDelete = false
    @State private var zoom: CGFloat = 1
    @State private var zoomBase: CGFloat = 1

    init(startItem: AlbumItem, onClose: @escaping () -> Void) {
        self.onClose = onClose
        _item = State(initialValue: startItem)
    }

    private var currentIndex: Int? {
        manager.albumItems.firstIndex { $0.id == item.id }
    }
    private var hasPrev: Bool { (currentIndex ?? 0) > 0 }
    private var hasNext: Bool {
        guard let i = currentIndex else { return false }
        return i < manager.albumItems.count - 1
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            content

            // 上/下压暗（白色控件压在亮色画面上的可读性保障）
            VStack(spacing: 0) {
                LinearGradient(colors: [.black.opacity(0.6), .clear],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: 150)
                Spacer()
                LinearGradient(colors: [.clear, .black.opacity(0.65)],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: 170)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)

            VStack(spacing: 0) {
                // 上夹头：铝条 + 帧号刻字
                HStack(spacing: 8) {
                    ScrewHead(size: 7)
                    Silkscreen(text: "FRAME", color: .black.opacity(0.45), size: 6, tracking: 1.6)
                    Text(AlbumDateFormat.short(item.createdAt))
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(.black.opacity(0.7))
                    Spacer()
                    if item.kind == .video {
                        Silkscreen(text: "MOV", color: .black.opacity(0.45), size: 6, tracking: 1.2)
                    }
                    Button { onClose() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.black.opacity(0.6))
                            .frame(width: 36, height: 36)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("关闭")
                    ScrewHead(size: 7)
                }
                .padding(.horizontal, 12)
                .frame(height: 44)
                .background(AluminumFace(tokens: ThemeStore.current))

                Spacer()

                // 下夹头：机械按键
                HStack(spacing: 10) {
                    navKey(system: "chevron.left", enabled: hasPrev) { move(-1) }
                        .accessibilityLabel("上一张")
                    Spacer(minLength: 0)
                    LabeledKey(tokens: ThemeStore.current, caption: "分享", radius: 5,
                               action: { showShare = true }) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(ThemeStore.current.ink)
                    }
                    .frame(width: 64)
                    .accessibilityLabel("分享")
                    LabeledKey(tokens: ThemeStore.current, caption: "删除", radius: 5,
                               action: { confirmDelete = true }) {
                        Image(systemName: "trash")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(ThemeStore.current.recRed)
                    }
                    .frame(width: 64)
                    .accessibilityLabel("删除")
                    Spacer(minLength: 0)
                    navKey(system: "chevron.right", enabled: hasNext) { move(1) }
                        .accessibilityLabel("下一张")
                }
                .padding(.horizontal, 14)
                .padding(.top, 10)
                .padding(.bottom, 12)
                .background(AluminumFace(tokens: ThemeStore.current))
            }
        }
        .task(id: item.url) { await load() }
        .onDisappear { player?.pause() }
        .sheet(isPresented: $showShare) {
            ShareSheet(items: [item.url])
        }
        .confirmationDialog("删除这条记录？", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("删除", role: .destructive) { deleteCurrent() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("只会从应用内相册移除，系统「照片」里的副本不受影响。")
        }
    }

    @ViewBuilder private var content: some View {
        if item.kind == .video {
            if let player {
                VideoPlayer(player: player)
                    .ignoresSafeArea()
            } else {
                ProgressView().tint(.white)
            }
        } else if let image {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .scaleEffect(zoom)
                .gesture(
                    MagnificationGesture()
                        .onChanged { scale in zoom = min(max(zoomBase * scale, 1), 4) }
                        .onEnded { _ in zoomBase = zoom }
                )
                .padding(12)
                .overlay(alignment: .bottomTrailing) {
                    if zoom > 1.05 {
                        Text(String(format: "%.1f×", zoom))
                            .font(CameraTheme.mono(10, weight: .semibold))
                            .foregroundColor(.black)
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(CameraTheme.amber)
                            .clipShape(Capsule())
                            .padding(16)
                    }
                }
        } else if isLoading {
            ProgressView().tint(.white)
        } else {
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle").foregroundColor(.white)
                Text("这张图打不开了").foregroundColor(.white.opacity(0.7))
                    .font(CameraTheme.mono(13))
            }
        }
    }

    private func navKey(system: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(enabled ? ThemeStore.current.ink : ThemeStore.current.inkDim.opacity(0.5))
                .frame(width: 54, height: 34)
                .contentShape(Rectangle())
        }
        .buttonStyle(PhysicalButtonStyle(tokens: ThemeStore.current, radius: 5))
        .disabled(!enabled)
    }

    @MainActor
    private func load() async {
        isLoading = true
        player?.pause()
        player = nil
        zoom = 1
        zoomBase = 1
        defer { isLoading = false }

        switch item.kind {
        case .photo:
            let maxPixel = max(UIScreen.main.bounds.width, UIScreen.main.bounds.height) * UIScreen.main.scale
            image = await MediaThumbnailLoader.thumbnail(url: item.url, maxPixel: maxPixel)
        case .video:
            image = nil
            let newPlayer = AVPlayer(url: item.url)
            player = newPlayer
            newPlayer.play()
        }
    }

    private func move(_ delta: Int) {
        guard let index = currentIndex else { return }
        let next = index + delta
        guard next >= 0, next < manager.albumItems.count else { return }
        image = nil
        item = manager.albumItems[next]
    }

    private func deleteCurrent() {
        player?.pause()
        // 注意 manager.delete 是异步删：这里先用删除前的列表算好"下一条"
        let items = manager.albumItems
        guard let index = items.firstIndex(where: { $0.id == item.id }) else {
            onClose()
            return
        }
        manager.delete(item)
        if index + 1 < items.count {
            item = items[index + 1]
        } else if index > 0 {
            item = items[index - 1]
        } else {
            onClose()
        }
    }
}
