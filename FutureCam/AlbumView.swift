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
    /// 接触印相模式：一冲出来就是一整张，和胶片真正拿到手的样子一样
    @State private var contactSheetMode = DebugHarness.shouldContactSheet
    /// 打开的是哪一卷；nil = 胶卷架
    @State private var openRoll: String?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 3)

    var body: some View {
        ZStack {
            // 洗印台：整机同一套铝拉丝。铺在最外层背景上，
            // 这样状态栏/灵动岛那块也一定是金属，不会被别的底色盖掉
            Color.clear

            VStack(spacing: 0) {
                if let openRoll {
                    rollHeader(openRoll)
                    if contactSheetMode {
                        contactSheet(sections.filter { $0.id == openRoll })
                    } else {
                        grid(sections.filter { $0.id == openRoll })
                    }
                } else {
                    header
                    if manager.albumItems.isEmpty || DebugHarness.shouldEmptyShelf {
                        emptyState
                    } else {
                        rollShelf
                    }
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
        .background(AluminumFace(tokens: ThemeStore.current).ignoresSafeArea())
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
            Silkscreen(text: "FILM ARCHIVE", color: CameraTheme.ink.opacity(0.6), size: 7, tracking: 2)
            Text(String(format: "%02d EXP", manager.albumItems.count))
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(.black.opacity(0.45))
            Spacer()
            Button {
                withAnimation(.easeOut(duration: 0.18)) { contactSheetMode.toggle() }
            } label: {
                Image(systemName: contactSheetMode ? "square.grid.2x2" : "film")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.black.opacity(0.55))
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(contactSheetMode ? "切回网格" : "切成接触印相")

            Text(contactSheetMode ? "印相" : "相册")
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

    /// 空货架：一排空罐位 + 一句话
    private var emptyState: some View {
        VStack(spacing: 18) {
            Spacer()

            HStack(alignment: .bottom, spacing: 14) {
                ForEach(0..<3, id: \.self) { i in
                    // 空位：只有罐子的轮廓，虚着等新卷
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(
                            CameraTheme.ink.opacity(i == 1 ? 0.28 : 0.16),
                            style: StrokeStyle(lineWidth: 1, dash: [3, 3])
                        )
                        .frame(width: i == 1 ? 46 : 38, height: i == 1 ? 84 : 70)
                }
            }
            .overlay(alignment: .bottom) {
                GrooveLine().offset(y: 10)
            }
            .padding(.bottom, 14)

            VStack(spacing: 6) {
                Text("货架还是空的")
                    .font(CameraTheme.mono(15, weight: .medium))
                    .foregroundColor(CameraTheme.ink.opacity(0.75))
                Text("装一卷，拍下第一张")
                    .font(CameraTheme.mono(11))
                    .foregroundColor(CameraTheme.ink.opacity(0.45))
            }

            Button {
                manager.closeAlbum()
                manager.showFilmSheet = true
            } label: {
                Text("去装卷")
                    .font(CameraTheme.mono(12, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 22)
                    .frame(height: 34)
                    .background(Capsule().fill(CameraTheme.amber))
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    /// 按卷分组的相册：一卷一段，像翻底片袋
    /// 接触印相：按卷分块，每卷一张黑纸，6 列密排，带齿孔
    /// 胶卷架：一排胶卷罐，点开才看里面的照片
    private var rollShelf: some View {
        // 瀑布流：两列各自堆叠，卡片高度不同也能各自贴紧，不留空洞。
        // LazyVGrid 会对齐行高，矮卡下面必然留白，所以这里手写两列。
        let indexed = Array(sections.enumerated())
        let left = indexed.filter { $0.offset % 2 == 0 }
        let right = indexed.filter { $0.offset % 2 == 1 }
        return ScrollView {
            HStack(alignment: .top, spacing: 12) {
                column(left)
                column(right)
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
    }

    private func column(_ items: [(offset: Int, element: AlbumSection)]) -> some View {
        VStack(spacing: 12) {
            ForEach(items, id: \.element.id) { item in
                Button {
                    withAnimation(.easeOut(duration: 0.18)) { openRoll = item.element.id }
                } label: {
                    rollCard(item.element, index: item.offset)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    /// 一卷的样子：大胶卷罐立在上面，信息与缩略图在下面
    private func rollCard(_ section: AlbumSection, index: Int) -> some View {
        // 越新的卷罐子越大，货架有前后错落，不是一排等高的格子
        let scale: CGFloat = index == 0 ? 1.16 : (index <= 2 ? 1.0 : 0.86)
        let roll = RollStore.shared.roll(id: section.id)
        let preset = roll.flatMap { FilmPreset(rawValue: $0.presetRaw) }
        let band = preset.map { canisterColor($0) } ?? CameraTheme.amber
        return VStack(spacing: 0) {
            // 罐子立在货架上
            MiniCanister(color: band, iso: preset.map { "\($0.nominalISO)" } ?? "", scale: scale)
                .padding(.top, 14 * scale)
                .padding(.bottom, 10)

            // 货架隔板：一道凹槽，罐子像是站在上面
            GrooveLine()
                .opacity(0.5)

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(section.title)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(CameraTheme.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Spacer(minLength: 0)
                    if let sub = section.subtitle {
                        Text(sub)
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(CameraTheme.ink.opacity(0.45))
                    }
                }

                HStack(spacing: 6) {
                    if let badge = rollBadge(roll) {
                        Text(badge.text)
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundColor(badge.warn ? CameraTheme.amber : CameraTheme.ink.opacity(0.45))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(
                                RoundedRectangle(cornerRadius: 3)
                                    .strokeBorder(badge.warn ? CameraTheme.amber.opacity(0.5)
                                                             : CameraTheme.ink.opacity(0.15),
                                                  lineWidth: 0.5)
                            )
                    } else {
                        Text(preset?.scene ?? "")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(CameraTheme.ink.opacity(0.4))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Text("\(section.items.count) 张")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(CameraTheme.ink.opacity(0.5))
                }

                HStack(spacing: 2) {
                    ForEach(section.items.prefix(3)) { item in
                        MediaThumbnail(item: item, maxPixel: 110)
                            .frame(height: 34)
                            .frame(maxWidth: .infinity)
                            .clipped()
                    }
                    Spacer(minLength: 0)
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 8)
            .padding(.bottom, 10)
        }
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(CameraTheme.ink.opacity(0.045))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(CameraTheme.ink.opacity(0.10), lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    /// 这一卷的使用状态：拍完 / 正在拍 / 中途收起
    private func rollBadge(_ roll: FilmRoll?) -> (text: String, warn: Bool)? {
        guard let roll else { return nil }
        if RollStore.shared.current.id == roll.id {
            return ("余 \(max(0, roll.capacity - roll.used)) 张", false)
        }
        if roll.used >= roll.capacity {
            return ("已拍完", false)
        }
        if roll.finishedAt != nil {
            return ("未拍完 · \(roll.used)/\(roll.capacity)", true)
        }
        return nil
    }

    /// 打开某一卷后的头：返回 + 卷信息 + 网格/印相切换
    private func rollHeader(_ rollID: String) -> some View {
        let section = sections.first { $0.id == rollID }
        return HStack(spacing: 8) {
            Button {
                withAnimation(.easeOut(duration: 0.18)) { openRoll = nil }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(CameraTheme.ink.opacity(0.6))
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.plain)

            Silkscreen(text: section?.title ?? "胶卷", color: CameraTheme.ink.opacity(0.6),
                       size: 7, tracking: 1.6)
            if let sub = section?.subtitle {
                Text(sub)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(CameraTheme.ink.opacity(0.4))
            }
            Spacer(minLength: 0)
            Button {
                contactSheetMode.toggle()
            } label: {
                Image(systemName: contactSheetMode ? "square.grid.2x2" : "film")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(CameraTheme.ink.opacity(0.55))
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.plain)
            Button { manager.closeAlbum() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(CameraTheme.ink.opacity(0.55))
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.top, 6)
        .padding(.bottom, 4)
    }

    private func contactSheet(_ list: [AlbumSection]) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                ForEach(list) { section in
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 6) {
                            Silkscreen(text: section.title, color: .white.opacity(0.7),
                                       size: 6.5, tracking: 1.8)
                            Rectangle().fill(.white.opacity(0.14)).frame(height: 1)
                            Text(section.countText)
                                .font(.system(size: 8, weight: .bold, design: .monospaced))
                                .foregroundColor(.white.opacity(0.45))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)

                        // 接触印相是「小而密」：固定 6 列、每格指甲盖大，
                        // 看的是整卷的节奏，不是单张细节
                        LazyVGrid(columns: Array(repeating: GridItem(.fixed(54), spacing: 3), count: 6),
                                  spacing: 3) {
                            ForEach(section.items) { item in
                                Button { detailItem = item } label: {
                                    MediaThumbnail(item: item, maxPixel: 160)
                                        .frame(width: 54, height: 36)
                                        .clipped()
                                        .overlay(Rectangle().strokeBorder(.white.opacity(0.10), lineWidth: 0.5))
                                }
                                .buttonStyle(.plain)
                            }
                            // 补空格子，让没拍满的卷也保持 6 列排面
                            ForEach(0..<max(0, 6 - section.items.count % 6), id: \.self) { _ in
                                Color.clear.frame(width: 54, height: 36)
                            }
                        }
                        .padding(.horizontal, 6)
                        .padding(.bottom, 8)

                        // 底边齿孔，和机身胶片仓同一套语言
                        HStack(spacing: 3) {
                            ForEach(0..<24, id: \.self) { _ in
                                RoundedRectangle(cornerRadius: 1)
                                    .fill(.white.opacity(0.07))
                                    .frame(height: 4)
                            }
                        }
                        .padding(.horizontal, 6)
                        .padding(.bottom, 6)
                    }
                    .background(Color(hex: 0x121314))
                }
            }
            .padding(.horizontal, 10)
        }
    }

    private func grid(_ list: [AlbumSection]) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                ForEach(list) { section in
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
    @State private var showDevelop = false
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
    /// 同一卷里的上一张：并排版式（练前/练后）需要第二张
    private func siblingImage() -> UIImage? {
        guard let idx = currentIndex else { return nil }
        let items = manager.albumItems
        guard idx + 1 < items.count else { return nil }
        let next = items[idx + 1]
        guard next.rollID == item.rollID, next.kind == .photo else { return nil }
        guard let data = try? Data(contentsOf: next.url) else { return nil }
        return UIImage(data: data)
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
                               action: { if image != nil { showShare = true } }) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(ThemeStore.current.ink)
                    }
                    .frame(width: 64)
                    .accessibilityLabel("分享")
                    LabeledKey(tokens: ThemeStore.current, caption: "冲印", radius: 5,
                               action: { showDevelop = true }) {
                        Image(systemName: "crop.rotate")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(ThemeStore.current.ink)
                    }
                    .frame(width: 64)
                    .accessibilityLabel("冲印")
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
            if let image {
                ShareCardSheet(item: item,
                               image: image,
                               secondImage: siblingImage(),
                               film: manager.presetLabel(for: item),
                               rollText: "VOL.\(manager.rollNumberText(for: item))",
                               frameText: manager.frameText(for: item))
            }
        }
        .sheet(isPresented: $showDevelop) {
            DevelopView(item: item) { updated in
                image = updated
                manager.refreshAlbum()
            }
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


/// 迷你胶卷罐：上下金属盖 + 中间彩色标签 + 顶部卷轴凸起。
/// 135 胶卷罐横放不下，这里竖着放在卡片左侧，一眼看出是「一筒胶片」。
struct MiniCanister: View {
    let color: Color
    /// ISO 数字，印在白色标签条上
    var iso: String = ""
    /// 相册里立着展示时的缩放（越新的卷越大）
    var scale: CGFloat = 1

    var body: some View {
        VStack(spacing: 0) {
            // 卷轴凸起
            RoundedRectangle(cornerRadius: 1.5)
                .fill(metalGradient)
                .frame(width: bodyWidth * 0.36, height: 6)

            // 上盖
            RoundedRectangle(cornerRadius: 1)
                .fill(metalGradient)
                .frame(height: capHeight)

            // 罐身：彩色标签 + 圆柱高光
            ZStack {
                color
                LinearGradient(colors: [.white.opacity(0.35), .clear, .black.opacity(0.22)],
                               startPoint: .leading, endPoint: .trailing)
                // 白色标签条 + ISO 数字：真实胶卷罐的辨识特征
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    ZStack {
                        Rectangle().fill(.white.opacity(0.92))
                        Text(iso)
                            .font(.system(size: 13 * scale, weight: .heavy, design: .monospaced))
                            .foregroundColor(color.opacity(0.9))
                    }
                    .frame(height: 22 * scale)
                    Spacer(minLength: 0)
                }
                VStack(spacing: 2) {
                    Rectangle().fill(.white.opacity(0.30)).frame(height: 0.5)
                    Spacer(minLength: 0)
                    Rectangle().fill(.black.opacity(0.18)).frame(height: 0.5)
                }
                .padding(.vertical, 4)
            }
            .frame(width: bodyWidth, height: bodyHeight)
            .clipped()

            // 下盖
            RoundedRectangle(cornerRadius: 1)
                .fill(metalGradient)
                .frame(height: capHeight)
        }
        .frame(width: bodyWidth)
        .clipShape(RoundedRectangle(cornerRadius: 3))
        .overlay(
            RoundedRectangle(cornerRadius: 3)
                .strokeBorder(.black.opacity(0.25), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.30), radius: 7 * scale, x: 0, y: 6 * scale)
    }

    private var bodyWidth: CGFloat { 62 * scale }
    private var bodyHeight: CGFloat { 76 * scale }
    private var capHeight: CGFloat { 15 * scale }

    private var metalGradient: LinearGradient {
        LinearGradient(colors: [Color(hex: 0xF2F4F6), Color(hex: 0xB9BEC3), Color(hex: 0x8E949A)],
                       startPoint: .top, endPoint: .bottom)
    }
}
