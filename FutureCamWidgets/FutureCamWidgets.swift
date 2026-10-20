import WidgetKit
import SwiftUI

/// 今日这一卷：还剩几张、是什么胶卷。
/// 只读一个共享摘要，不碰照片，也不联网。
struct RollEntry: TimelineEntry {
    let date: Date
    let film: String
    let rollNumber: Int
    let used: Int
    let capacity: Int
    let tint: Color
}

struct RollProvider: TimelineProvider {
    private struct Snapshot: Codable {
        var film: String
        var rollNumber: Int
        var used: Int
        var capacity: Int
        var colorHex: String
        var updatedAt: Date
    }

    private func load() -> Snapshot? {
        guard let defaults = UserDefaults(suiteName: "group.com.futurecam.app"),
              let data = defaults.data(forKey: "futurecam.roll.snapshot")
        else { return nil }
        return try? JSONDecoder().decode(Snapshot.self, from: data)
    }

    func placeholder(in context: Context) -> RollEntry {
        RollEntry(date: Date(), film: "松石 400", rollNumber: 3, used: 7,
                  capacity: 36, tint: Color(red: 0.18, green: 0.49, blue: 0.33))
    }

    func getSnapshot(in context: Context, completion: @escaping (RollEntry) -> Void) {
        completion(entry(from: load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<RollEntry>) -> Void) {
        let entry = entry(from: load())
        // 每 30 分钟刷一次；拍完照 App 会主动 reload，所以不会滞后
        let next = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date()
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    private func entry(from snapshot: Snapshot?) -> RollEntry {
        guard let s = snapshot else {
            return RollEntry(date: Date(), film: "未装卷", rollNumber: 0,
                             used: 0, capacity: 36, tint: .gray)
        }
        return RollEntry(date: Date(), film: s.film, rollNumber: s.rollNumber,
                         used: s.used, capacity: s.capacity, tint: Color(hexString: s.colorHex))
    }
}

struct RollWidgetView: View {
    let entry: RollEntry

    private var remaining: Int { max(0, entry.capacity - entry.used) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Circle().fill(entry.tint).frame(width: 6, height: 6)
                Text(entry.film)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.9))
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text("VOL.\(String(format: "%02d", entry.rollNumber))")
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.45))
            }

            Spacer(minLength: 0)

            Text("\(remaining)")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundColor(.white)
            Text("还剩 \(remaining) 张")
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.55))

            // 36 格的进度条，和显影页同一套语言
            HStack(spacing: 2) {
                ForEach(0..<entry.capacity, id: \.self) { i in
                    Rectangle()
                        .fill(i < entry.used ? entry.tint.opacity(0.9) : .white.opacity(0.15))
                        .frame(height: 3)
                }
            }
        }
        .padding(12)
        .containerBackground(for: .widget) {
            LinearGradient(colors: [Color(white: 0.12), Color(white: 0.05)],
                           startPoint: .top, endPoint: .bottom)
        }
    }
}

@main
struct FutureCamWidgets: WidgetBundle {
    var body: some Widget {
        RollWidget()
    }
}

struct RollWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "FutureCamRoll", provider: RollProvider()) { entry in
            RollWidgetView(entry: entry)
        }
        .configurationDisplayName("这一卷")
        .description("还剩几张，是什么胶卷。")
        .supportedFamilies([.systemSmall])
    }
}

extension Color {
    init(hexString: String) {
        var value: UInt64 = 0
        let clean = hexString.hasPrefix("#") ? String(hexString.dropFirst()) : hexString
        Scanner(string: clean).scanHexInt64(&value)
        self.init(red: Double((value >> 16) & 0xFF) / 255,
                  green: Double((value >> 8) & 0xFF) / 255,
                  blue: Double(value & 0xFF) / 255)
    }
}
