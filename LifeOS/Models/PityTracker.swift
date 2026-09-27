import Foundation
import SwiftData

enum PityGuaranteeKind: String, Codable, CaseIterable, Identifiable {
    case none
    case fiftyFifty
    case seventyFiveTwentyFive
    case sixtyForty
    case eightyTwenty
    case alwaysGuaranteed
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none: "No featured guarantee"
        case .fiftyFifty: "50/50"
        case .seventyFiveTwentyFive: "75/25"
        case .sixtyForty: "60/40"
        case .eightyTwenty: "80/20"
        case .alwaysGuaranteed: "Always guaranteed"
        case .custom: "Custom split"
        }
    }

    /// Coin-flip banners go to guaranteed after a loss; the rest just reset pity.
    var usesFeaturedCoinFlip: Bool {
        switch self {
        case .fiftyFifty, .seventyFiveTwentyFive, .sixtyForty, .eightyTwenty, .custom:
            true
        case .none, .alwaysGuaranteed:
            false
        }
    }

    var chipLabel: String {
        switch self {
        case .none: "Standard pool"
        case .fiftyFifty: "50/50"
        case .seventyFiveTwentyFive: "75/25"
        case .sixtyForty: "60/40"
        case .eightyTwenty: "80/20"
        case .alwaysGuaranteed: "Guaranteed"
        case .custom: "Custom"
        }
    }
}

@Model
final class PityTracker {
    @Attribute(.unique) var id: UUID
    var gameRaw: String
    var name: String
    var presetKey: String?
    var sortOrder: Int
    var hardPity: Int
    var softPity: Int?
    var guaranteeKindRaw: String
    var fatePointCap: Int
    var currentPity: Int
    var lifetimePulls: Int
    var isGuaranteed: Bool
    var fatePoints: Int
    var guaranteeLabel: String? = nil
    var lastDropName: String? = nil
    var lastDropPity: Int? = nil
    var lastDropAt: Date? = nil
    var lastDropWasFeatured: Bool? = nil
    var createdAt: Date
    var updatedAt: Date

    var game: GameSubCategory {
        get { GameSubCategory(rawValue: gameRaw) ?? .genshinImpact }
        set { gameRaw = newValue.rawValue }
    }

    var guaranteeKind: PityGuaranteeKind {
        get { PityGuaranteeKind(rawValue: guaranteeKindRaw) ?? .none }
        set { guaranteeKindRaw = newValue.rawValue }
    }

    var isPreset: Bool { presetKey != nil }

    var lastDropCaption: String? {
        guard let pity = lastDropPity else { return nil }
        let name = lastDropName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if name.isEmpty {
            return "Last 5★ at \(pity)"
        }
        return "Last: \(name) · \(pity)"
    }

    var snapshot: PitySnapshot {
        PitySnapshot(
            currentPity: currentPity,
            lifetimePulls: lifetimePulls,
            isGuaranteed: isGuaranteed,
            fatePoints: fatePoints,
            hardPity: hardPity,
            softPity: softPity,
            guaranteeKind: guaranteeKind,
            fatePointCap: fatePointCap,
            guaranteeLabel: guaranteeLabel,
            lastDropName: lastDropName,
            lastDropPity: lastDropPity,
            lastDropAt: lastDropAt,
            lastDropWasFeatured: lastDropWasFeatured
        )
    }

    init(
        id: UUID = UUID(),
        game: GameSubCategory,
        name: String,
        presetKey: String? = nil,
        sortOrder: Int = 0,
        hardPity: Int,
        softPity: Int? = nil,
        guaranteeKind: PityGuaranteeKind,
        fatePointCap: Int = 0,
        currentPity: Int = 0,
        lifetimePulls: Int = 0,
        isGuaranteed: Bool = false,
        fatePoints: Int = 0,
        guaranteeLabel: String? = nil,
        lastDropName: String? = nil,
        lastDropPity: Int? = nil,
        lastDropAt: Date? = nil,
        lastDropWasFeatured: Bool? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.gameRaw = game.rawValue
        self.name = name
        self.presetKey = presetKey
        self.sortOrder = sortOrder
        self.hardPity = hardPity
        self.softPity = softPity
        self.guaranteeKindRaw = guaranteeKind.rawValue
        self.fatePointCap = fatePointCap
        self.currentPity = currentPity
        self.lifetimePulls = lifetimePulls
        self.isGuaranteed = isGuaranteed
        self.fatePoints = fatePoints
        self.guaranteeLabel = guaranteeLabel
        self.lastDropName = lastDropName
        self.lastDropPity = lastDropPity
        self.lastDropAt = lastDropAt
        self.lastDropWasFeatured = lastDropWasFeatured
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    func apply(_ snapshot: PitySnapshot) {
        currentPity = snapshot.currentPity
        lifetimePulls = snapshot.lifetimePulls
        isGuaranteed = snapshot.isGuaranteed
        fatePoints = snapshot.fatePoints
        hardPity = snapshot.hardPity
        softPity = snapshot.softPity
        guaranteeKind = snapshot.guaranteeKind
        fatePointCap = snapshot.fatePointCap
        guaranteeLabel = snapshot.guaranteeLabel
        lastDropName = snapshot.lastDropName
        lastDropPity = snapshot.lastDropPity
        lastDropAt = snapshot.lastDropAt
        lastDropWasFeatured = snapshot.lastDropWasFeatured
        updatedAt = .now
    }
}
