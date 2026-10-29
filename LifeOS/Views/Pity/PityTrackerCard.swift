import SwiftUI
import SwiftData

struct PityTrackerCard: View {
    let tracker: PityTracker
    var canUndo: Bool
    var canMoveUp: Bool
    var canMoveDown: Bool
    var onApply: (PitySnapshot) -> Void
    var onUndo: () -> Void
    var onEdit: () -> Void
    var onDelete: () -> Void
    var onMoveUp: () -> Void
    var onMoveDown: () -> Void

    @State private var showingOutcome = false

    private var state: PitySnapshot { tracker.snapshot }
    private var proximity: PityProximity { PityRules.proximity(for: state) }
    private var heat: Color { PityVisuals.heatColor(proximity: proximity, game: tracker.game) }

    /// A freshly seeded preset has `updatedAt == createdAt`; calling that "Updated today"
    /// would suggest a pull session that never happened.
    private var lastUpdatedText: String {
        guard tracker.updatedAt.timeIntervalSince(tracker.createdAt) > 1 else {
            return "Not updated yet"
        }
        return DateFormatting.lastUpdatedLine(for: tracker.updatedAt)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            progressBar
            chips
            if tracker.fatePointCap > 0 {
                fateRow
            }
            sessionControls
            if canUndo {
                Button("Undo last") {
                    Haptics.light()
                    onUndo()
                }
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .foregroundStyle(LifeOSTheme.softText)
            }
        }
        .padding(14)
        .background(cardBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(PityVisuals.strokeColor(proximity: proximity, game: tracker.game), lineWidth: proximity >= .softPity ? 1.5 : 1)
        )
        .animation(.easeInOut(duration: 0.22), value: tracker.currentPity)
        .animation(.easeInOut(duration: 0.22), value: proximity)
        .contextMenu {
            if canMoveUp {
                Button("Move Up", systemImage: "arrow.up") { onMoveUp() }
            }
            if canMoveDown {
                Button("Move Down", systemImage: "arrow.down") { onMoveDown() }
            }
            Button("Edit Banner", systemImage: "pencil", action: onEdit)
            Button("Reset Pity", systemImage: "arrow.counterclockwise") {
                onApply(PityRules.resetPityOnly(state))
            }
            Button(tracker.isPreset ? "Remove Preset" : "Delete Banner", systemImage: "trash", role: .destructive, action: onDelete)
        }
        .confirmationDialog("What did you get?", isPresented: $showingOutcome, titleVisibility: .visible) {
            Button(featuredLabel) { applyFiveStar(.featured) }
            Button(offBannerLabel) { applyFiveStar(.offBanner) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(outcomeMessage)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(heat)
                .frame(width: 4)
                .padding(.vertical, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text(tracker.name)
                    .font(.system(.body, design: .rounded, weight: .semibold))
                    .foregroundStyle(.white)

                Text(lastUpdatedText)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(LifeOSTheme.softText)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(tracker.currentPity)")
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .foregroundStyle(PityVisuals.countColor(proximity: proximity, game: tracker.game))
                    .contentTransition(.numericText())
                Text("/ \(tracker.hardPity)")
                    .font(.system(.caption2, design: .rounded, weight: .medium))
                    .foregroundStyle(LifeOSTheme.softText)
            }
        }
    }

    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(LifeOSTheme.stroke)
                Capsule()
                    .fill(heat)
                    .frame(width: max(4, geo.size.width * PityRules.progress(for: state)))
            }
        }
        .frame(height: proximity >= .softPity ? 8 : 6)
    }

    private var chips: some View {
        HStack(spacing: 6) {
            chipButton(PityVisuals.guaranteeChip(for: state), emphasized: state.isGuaranteed || state.guaranteeKind == .alwaysGuaranteed) {
                guard state.guaranteeKind.usesFeaturedCoinFlip else { return }
                Haptics.selection()
                onApply(PityRules.toggleGuarantee(state))
            }

            if let label = PityVisuals.proximityLabel(for: state) {
                chip(label, fill: heat)
            }
        }
    }

    private var fateRow: some View {
        HStack {
            Text("Path \(tracker.fatePoints)/\(tracker.fatePointCap)")
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
            Spacer()
            Stepper(
                "",
                value: Binding(
                    get: { tracker.fatePoints },
                    set: { onApply(PityRules.setFatePoints(state, to: $0)) }
                ),
                in: 0...tracker.fatePointCap
            )
            .labelsHidden()
        }
    }

    private var sessionControls: some View {
        HStack(spacing: 8) {
            quietButton("−10") {
                applyIncrement(-10)
            }
            .disabled(tracker.currentPity == 0)
            quietButton("−1") {
                applyIncrement(-1)
            }
            .disabled(tracker.currentPity == 0)

            Spacer(minLength: 4)

            capsuleButton("+1") {
                applyIncrement(1)
            }
            capsuleButton("+10") {
                applyIncrement(10)
            }
            gotFiveStarButton
        }
    }

    private var gotFiveStarButton: some View {
        Button {
            if PityRules.needsOutcomePrompt(for: state) {
                showingOutcome = true
            } else {
                applyFiveStar(.featured)
            }
        } label: {
            Text("Got 5★")
                .font(.system(.caption, design: .rounded, weight: .bold))
                .foregroundStyle(LifeOSTheme.canvas)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(heat, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Got five star")
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(LifeOSTheme.elevated)
            .overlay {
                if proximity >= .softPity {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(heat.opacity(proximity >= .atHard ? 0.14 : 0.08))
                }
            }
    }

    private var featuredLabel: String {
        if tracker.fatePointCap > 0 || tracker.guaranteeKind == .seventyFiveTwentyFive {
            return "Wanted weapon"
        }
        return "Featured"
    }

    private var offBannerLabel: String {
        if tracker.fatePointCap > 0 || tracker.guaranteeKind == .seventyFiveTwentyFive {
            return "Not the one"
        }
        return "Lost 50/50"
    }

    private var outcomeMessage: String {
        if tracker.fatePointCap > 0 {
            return "Wanted weapon resets path. Not the one adds a fate point."
        }
        if tracker.guaranteeKind == .seventyFiveTwentyFive {
            return "Wanted weapon stays on 75/25. Not the one moves you to guaranteed."
        }
        return "Featured stays on the current split. Off-banner moves you to guaranteed."
    }

    private func applyIncrement(_ amount: Int) {
        let next = amount > 0
            ? PityRules.increment(state, by: amount)
            : PityRules.decrement(state, by: abs(amount))
        let before = proximity
        let after = PityRules.proximity(for: next)
        if after > before {
            Haptics.warning()
        } else if amount > 0 {
            Haptics.light()
        } else {
            Haptics.selection()
        }
        onApply(next)
    }

    private func applyFiveStar(_ outcome: PityFiveStarOutcome) {
        Haptics.success()
        onApply(PityRules.applyFiveStar(state, outcome: outcome))
    }

    private func chip(_ title: String, fill: Color) -> some View {
        Text(title)
            .font(.system(.caption2, design: .rounded, weight: .bold))
            .foregroundStyle(LifeOSTheme.canvas)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(fill, in: Capsule())
    }

    private func chipButton(_ title: String, emphasized: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(.caption2, design: .rounded, weight: .bold))
                .foregroundStyle(emphasized ? LifeOSTheme.canvas : .white.opacity(0.9))
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(emphasized ? heat : LifeOSTheme.stroke, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func capsuleButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(.caption, design: .rounded, weight: .bold))
                .foregroundStyle(LifeOSTheme.canvas)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(LifeOSTheme.accent.opacity(0.9), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func quietButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .foregroundStyle(LifeOSTheme.softText)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(LifeOSTheme.stroke, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}
