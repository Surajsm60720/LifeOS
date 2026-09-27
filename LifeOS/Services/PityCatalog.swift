import Foundation
import SwiftData

enum PityCatalog {
    struct Preset: Equatable, Sendable {
        let key: String
        let game: GameSubCategory
        let name: String
        let hardPity: Int
        let softPity: Int?
        let guaranteeKind: PityGuaranteeKind
        let fatePointCap: Int
        let sortOrder: Int

        func makeTracker() -> PityTracker {
            PityTracker(
                game: game,
                name: name,
                presetKey: key,
                sortOrder: sortOrder,
                hardPity: hardPity,
                softPity: softPity,
                guaranteeKind: guaranteeKind,
                fatePointCap: fatePointCap
            )
        }
    }

    static let presets: [Preset] = [
        Preset(key: "gi.character", game: .genshinImpact, name: "Character Event Wish", hardPity: 90, softPity: 74, guaranteeKind: .fiftyFifty, fatePointCap: 0, sortOrder: 0),
        Preset(key: "gi.weapon", game: .genshinImpact, name: "Weapon Event Wish", hardPity: 80, softPity: 63, guaranteeKind: .fiftyFifty, fatePointCap: 2, sortOrder: 1),
        Preset(key: "gi.standard", game: .genshinImpact, name: "Standard Wish", hardPity: 90, softPity: 74, guaranteeKind: .none, fatePointCap: 0, sortOrder: 2),

        Preset(key: "hsr.character", game: .honkaiStarRail, name: "Character Event Warp", hardPity: 90, softPity: 74, guaranteeKind: .fiftyFifty, fatePointCap: 0, sortOrder: 0),
        Preset(key: "hsr.lightCone", game: .honkaiStarRail, name: "Light Cone Event Warp", hardPity: 80, softPity: 65, guaranteeKind: .seventyFiveTwentyFive, fatePointCap: 0, sortOrder: 1),
        Preset(key: "hsr.standard", game: .honkaiStarRail, name: "Standard Warp", hardPity: 90, softPity: 74, guaranteeKind: .none, fatePointCap: 0, sortOrder: 2),

        Preset(key: "wuwa.resonator", game: .wutheringWaves, name: "Featured Resonator", hardPity: 80, softPity: 65, guaranteeKind: .fiftyFifty, fatePointCap: 0, sortOrder: 0),
        Preset(key: "wuwa.weapon", game: .wutheringWaves, name: "Featured Weapon", hardPity: 80, softPity: 65, guaranteeKind: .alwaysGuaranteed, fatePointCap: 0, sortOrder: 1),
        Preset(key: "wuwa.standard", game: .wutheringWaves, name: "Standard Convenes", hardPity: 80, softPity: 65, guaranteeKind: .alwaysGuaranteed, fatePointCap: 0, sortOrder: 2),
    ]

    @MainActor
    static func existingKeys(in modelContext: ModelContext) -> Set<String> {
        let existing = (try? modelContext.fetch(FetchDescriptor<PityTracker>())) ?? []
        return Set(existing.compactMap(\.presetKey))
    }

    /// First launch / after a full wipe: seed every preset if the store has none.
    @MainActor
    static func seedIfEmpty(modelContext: ModelContext) {
        let existing = (try? modelContext.fetch(FetchDescriptor<PityTracker>())) ?? []
        guard existing.isEmpty else { return }
        for preset in presets {
            modelContext.insert(preset.makeTracker())
        }
        try? modelContext.save()
    }

    /// Re-adds official banners whose `presetKey` is missing. Does not overwrite live pity.
    @MainActor
    static func seedMissing(modelContext: ModelContext) {
        let keys = existingKeys(in: modelContext)
        var inserted = false
        for preset in presets where !keys.contains(preset.key) {
            modelContext.insert(preset.makeTracker())
            inserted = true
        }
        if inserted {
            try? modelContext.save()
        }
    }
}
