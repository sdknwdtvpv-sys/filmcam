import StoreKit
import SwiftUI

/// 胶卷包：把胶片分成免费与付费两组。
/// 卖的是"胶卷"不是"订阅"——点一卷看到价格，这个动作本身就能理解。
enum FilmPack: String, CaseIterable, Identifiable {
    case base        // 免费：原生 + 琥珀 + 松石 + 银盐 + 褪色电影
    case wander      // 远行：钴蓝 / 暮金 / 石板 / 薄荷
    case nocturne    // 夜行：铁锈 / 霜白 / 赭石 / 深潭

    var id: String { rawValue }

    var title: String {
        switch self {
        case .base: return "随机器附赠"
        case .wander: return "远行"
        case .nocturne: return "夜行"
        }
    }

    var productID: String? {
        switch self {
        case .base: return nil
        case .wander: return "com.futurecam.app.pack.wander"
        case .nocturne: return "com.futurecam.app.pack.nocturne"
        }
    }

    var hint: String {
        switch self {
        case .base: return ""
        case .wander: return "四卷偏日间与风光"
        case .nocturne: return "四卷偏暗光与夜色"
        }
    }

    var films: [FilmPreset] {
        switch self {
        case .base: return [.neutral, .kodakGold, .fuji400, .classicBnw, .fadedCinema]
        case .wander: return [.cinematic, .duskGold, .slate, .mint]
        case .nocturne: return [.rust, .frost, .ochre, .abyss]
        }
    }

    static func pack(for preset: FilmPreset) -> FilmPack {
        allCases.first { $0.films.contains(preset) } ?? .base
    }
}

/// 购买状态：StoreKit 2。
/// 注意：产品在 App Store Connect 里配好之前，这里会拿不到商品，
/// 那就**全部放行**——开发期与审核前不能把自己锁死。
@MainActor
final class PurchaseStore: ObservableObject {
    static let shared = PurchaseStore()

    @Published private(set) var products: [String: Product] = [:]
    @Published private(set) var purchased: Set<String> = []
    @Published private(set) var storeAvailable = false
    @Published var lastError: String?

    private init() {}

    /// 产品没配好时视为全部解锁
    var isOpenElsewhere: Bool { !storeAvailable || products.isEmpty }

    func isUnlocked(_ preset: FilmPreset) -> Bool {
        let pack = FilmPack.pack(for: preset)
        guard let id = pack.productID else { return true }
        if isOpenElsewhere { return true }
        return purchased.contains(id)
    }

    func priceText(for pack: FilmPack) -> String? {
        guard let id = pack.productID else { return nil }
        if isOpenElsewhere { return "可拍" }
        return products[id]?.displayPrice
    }

    func start() async {
        do {
            let ids = FilmPack.allCases.compactMap(\.productID)
            let fetched = try await Product.products(for: ids)
            products = Dictionary(uniqueKeysWithValues: fetched.map { ($0.id, $0) })
            storeAvailable = !fetched.isEmpty
            await refreshEntitlements()
        } catch {
            lastError = error.localizedDescription
            storeAvailable = false
        }
    }

    func refreshEntitlements() async {
        var owned = Set<String>()
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result {
                owned.insert(transaction.productID)
            }
        }
        purchased = owned
    }

    @discardableResult
    func purchase(_ pack: FilmPack) async -> Bool {
        guard let id = pack.productID, let product = products[id] else { return false }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                if case .verified(let transaction) = verification {
                    await transaction.finish()
                    await refreshEntitlements()
                    return true
                }
                return false
            case .pending, .userCancelled:
                return false
            @unknown default:
                return false
            }
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }
}
