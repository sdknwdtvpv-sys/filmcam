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
            CameraTheme.bgDeep.ignoresSafeArea()

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
        HStack(alignment: .firstTextBaseline) {
            Text("相册")
                .foregroundColor(CameraTheme.ink)
                .font(CameraTheme.mono(18, weight: .semibold))
            if !manager.albumItems.isEmpty {
                Text("\(manager.albumItems.count)")
                    .font(CameraTheme.mono(12, weight: .medium))
                    .foregroundColor(CameraTheme.inkDim)
            }
            Spacer()
            Button { manager.closeAlbum() } label: {
                Image(systemName: "xmark")
                    .foregroundColor(CameraTheme.ink)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("关闭相册")
        }
        .padding(.leading, 20)
        .padding(.trailing, 8)
        .padding(.top, 8)
        .padding(.bottom, 8)
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

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(manager.albumItems) { item in
                    Button { detailItem = item } label: {
                        MediaThumbnail(item: item, maxPixel: 420)
                            .aspectRatio(0.7, contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(item.kind == .video ? "视频" : "照片")，\(AlbumDateFormat.short(item.createdAt))")
                }
            }
            .padding(8)
        }
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

            VStack {
                HStack {
                    Text(AlbumDateFormat.short(item.createdAt))
                        .font(CameraTheme.mono(11, weight: .medium))
                        .foregroundColor(.white.opacity(0.9))
                    Spacer()
                    Button { onClose() } label: {
                        Image(systemName: "xmark").foregroundColor(.white)
                            .frame(width: 44, height: 44)
                            .background(Circle().fill(Color.white.opacity(0.16)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("关闭")
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)

                Spacer()

                HStack(spacing: 0) {
                    navButton(system: "chevron.left", enabled: hasPrev) { move(-1) }
                        .accessibilityLabel("上一张")
                    Spacer()
                    Button { showShare = true } label: {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 20))
                            .foregroundColor(.white)
                            .frame(width: 56, height: 56)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("分享")
                    Spacer()
                    Button { confirmDelete = true } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 19))
                            .foregroundColor(CameraTheme.recRed)
                            .frame(width: 56, height: 56)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("删除")
                    Spacer()
                    navButton(system: "chevron.right", enabled: hasNext) { move(1) }
                        .accessibilityLabel("下一张")
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 24)
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

    private func navButton(system: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 20))
                .foregroundColor(enabled ? .white : .white.opacity(0.25))
                .frame(width: 56, height: 56)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
