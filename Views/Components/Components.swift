import SwiftUI

// MARK: - Provider glyph

/// Provider mark: the provider's symbol in its brand tint on a soft wash of
/// the same colour. Identity without a wall of saturated tiles.
struct ProviderGlyph: View {
    let descriptor: ProviderDescriptor
    var size: CGFloat = 40

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.2, style: .continuous)
        shape
            .fill(descriptor.tint.opacity(Theme.Wash.opacity(scheme)))
            .overlay { shape.strokeBorder(descriptor.tint.opacity(scheme == .dark ? 0.22 : 0.14), lineWidth: 0.75) }
            .overlay(
                Image(systemName: descriptor.symbol)
                    .font(.system(size: size * 0.44, weight: .semibold))
                    .foregroundStyle(descriptor.tint))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

// MARK: - Gauges

/// Consumption bar: ink while healthy, amber/coral only when at stake.
struct UsageBar: View {
    let fraction: Double
    var tint: Color = Theme.gauge
    var height: CGFloat = 8

    private var clamped: Double { min(max(fraction, 0), 1) }

    var body: some View {
        let color = Theme.severity(clamped, tint: tint)
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: Theme.Radius.bar).fill(Theme.track)
                RoundedRectangle(cornerRadius: Theme.Radius.bar)
                    .fill(color)
                    .frame(width: max(proxy.size.width * clamped, clamped > 0 ? height : 0))
            }
        }
        .frame(height: height)
        .animation(.settle, value: clamped)
        .accessibilityHidden(true)
    }
}

/// Circular allowance gauge.
struct UsageRing: View {
    let fraction: Double
    var tint: Color = Theme.gauge
    var size: CGFloat = 64
    var lineWidth: CGFloat = 7
    var showsLabel = true

    private var clamped: Double { min(max(fraction, 0), 1) }

    var body: some View {
        let color = Theme.severity(clamped, tint: tint)
        ZStack {
            Circle().stroke(Theme.track, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: clamped)
                .stroke(
                    color,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.settle, value: clamped)
            if showsLabel {
                Text("\(Int((clamped * 100).rounded()))%")
                    .font(.system(size: size * 0.24, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Theme.ink)
                    .minimumScaleFactor(0.6)
                    .padding(lineWidth)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Terminal-style gauge drawn with block characters: `██████░░░░`.
struct BlockBar: View {
    let fraction: Double
    var cells = 10
    var font: Font = .mono(.footnote)
    var tint: Color = Theme.gauge
    /// Off for shares (e.g. spend split), which are not limits and must not
    /// turn amber or red.
    var showsSeverity = true

    var body: some View {
        let clamped = min(max(fraction, 0), 1)
        let filled = clamped > 0 ? max(Int((clamped * Double(cells)).rounded()), 1) : 0
        HStack(spacing: 0) {
            Text(String(repeating: "█", count: filled))
                .foregroundStyle(showsSeverity ? Theme.severity(clamped, tint: tint) : tint)
            Text(String(repeating: "░", count: cells - filled))
                .foregroundStyle(Theme.inkTertiary.opacity(0.7))
        }
        .font(font)
        .lineLimit(1)
        .fixedSize()
        .accessibilityHidden(true)
    }
}

/// Full-width segmented meter — the shape-drawn cousin of `BlockBar`, for
/// places where the bar should span its container.
struct SegmentedMeter: View {
    let fraction: Double
    var height: CGFloat = 8
    var segment: CGFloat = 5
    var gap: CGFloat = 2
    var tint: Color = Theme.gauge
    /// Off for progress that is not a limit (splash, onboarding).
    var showsSeverity = true

    var body: some View {
        let clamped = min(max(fraction, 0), 1)
        let color = showsSeverity ? Theme.severity(clamped, tint: tint) : tint
        GeometryReader { proxy in
            let count = max(Int((proxy.size.width + gap) / (segment + gap)), 1)
            let filled = clamped > 0 ? max(Int((clamped * Double(count)).rounded()), 1) : 0
            HStack(spacing: gap) {
                ForEach(0..<count, id: \.self) { index in
                    Rectangle()
                        .fill(index < filled ? color : Theme.track)
                        .frame(width: segment)
                }
            }
        }
        .frame(height: height)
        .animation(.settle, value: clamped)
        .accessibilityHidden(true)
    }
}

// MARK: - Labels

/// Small labelled figure used for secondary metrics.
struct StatTile: View {
    let metric: UsageMetric

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            Text(metric.title)
                .font(.caption)
                .foregroundStyle(Theme.inkSecondary)
                .lineLimit(1)
            Text(MetricText.value(metric, includeLimit: metric.unit != .usd))
                .font(.system(.callout, design: .rounded).weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// Inline advisory used for provider caveats, errors and per-reading notes.
struct Callout: View {
    enum Level { case info, watch, critical }

    let text: String
    var level: Level = .info

    private var symbol: String {
        switch level {
        case .info: return "info.circle.fill"
        case .watch: return "exclamationmark.triangle.fill"
        case .critical: return "exclamationmark.octagon.fill"
        }
    }

    private var tint: Color {
        switch level {
        case .info: return Theme.brand
        case .watch: return Theme.watch
        case .critical: return Theme.critical
        }
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.m) {
            Image(systemName: symbol)
                .font(.subheadline)
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            Text(text)
                .font(.footnote)
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Theme.Space.l)
        .padding(.vertical, Theme.Space.m)
        .background(tint.opacity(Theme.Wash.dark),
                    in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// Countdown chip, e.g. "Resets in 4h 12m".
struct ResetChip: View {
    let date: Date
    var compact = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            if let text = Format.countdown(to: date, from: context.date) {
                Label(compact ? text : "Resets in \(text)", systemImage: "clock.arrow.circlepath")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Theme.inkSecondary)
                    .labelStyle(.titleAndIcon)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Theme.fillSubtle, in: Capsule())
            }
        }
    }
}

/// Section heading for grouped content.
struct SectionHeader<Trailing: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                Text(title)
                    .eyebrow()
                if let subtitle {
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(Theme.inkSecondary)
                }
            }
            Spacer(minLength: Theme.Space.s)
            trailing
        }
        // Inset to the row content inside the card below, like grouped lists.
        .padding(.horizontal, Theme.Space.l)
        .accessibilityAddTraits(.isHeader)
    }
}

extension SectionHeader where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil) {
        self.init(title: title, subtitle: subtitle) { EmptyView() }
    }
}

/// Small status capsule: "Live", "Error", "Stale".
struct StatusPill: View {
    let text: String
    let color: Color
    var symbol: String?

    var body: some View {
        HStack(spacing: 4) {
            if let symbol {
                Image(systemName: symbol).font(.system(size: Theme.TypeScale.micro, weight: .bold))
            } else {
                Circle().fill(color).frame(width: 6, height: 6)
            }
            Text(text).font(.caption2.weight(.semibold))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(Theme.Wash.dark), in: Capsule())
    }
}

// MARK: - Pressable

/// Cards depress slightly under the finger, so a tile reads as one target.
struct PressableCardStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.press, value: configuration.isPressed)
    }
}

// MARK: - Metric text

/// Shared metric wording, so tiles, rows, cards and accessibility labels
/// never disagree.
enum MetricText {
    static func value(_ metric: UsageMetric, includeLimit: Bool = false) -> String {
        guard let value = metric.displayValue else { return "—" }
        let formatted = Format.value(value, unit: metric.unit, currencyCode: metric.currencyCode)
        guard includeLimit, let limit = metric.limit, metric.unit != .percent else { return formatted }
        return "\(formatted) / \(Format.value(limit, unit: metric.unit, currencyCode: metric.currencyCode))"
    }

    /// "Credits left of $50.00 · key credit limit"
    static func caption(_ metric: UsageMetric) -> String {
        var parts = [metric.title]
        if let limit = metric.limit, metric.unit != .percent {
            parts.append("of \(Format.value(limit, unit: metric.unit, currencyCode: metric.currencyCode))")
        }
        var text = parts.joined(separator: " ")
        if let caption = metric.caption { text += " · \(caption)" }
        return text
    }

    static func accessibility(_ metric: UsageMetric, name: String) -> String {
        var summary = "\(name), \(value(metric)), \(caption(metric))"
        if let fraction = metric.fraction {
            summary += ", \(Int((fraction * 100).rounded())) percent used"
        }
        if let reset = metric.resetsAt, let countdown = Format.countdown(to: reset) {
            summary += ", resets in \(countdown)"
        }
        return summary
    }
}

// MARK: - Buttons

/// The one primary action on a screen: a solid accent slab, card-radius
/// corners, monospaced label. 50 pt tall so it lines up with form rows.
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.mono(.callout, weight: .semibold))
            .foregroundStyle(Theme.onAccent)
            .frame(maxWidth: .infinity, minHeight: 50)
            .padding(.horizontal, Theme.Space.l)
            .background(Theme.accent, in: RoundedRectangle(cornerRadius: Theme.Radius.control + 4,
                                                           style: .continuous))
            .opacity(isEnabled ? (configuration.isPressed ? 0.82 : 1) : 0.38)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.press, value: configuration.isPressed)
            .contentShape(Rectangle())
    }
}

/// Secondary action: a raised surface with a hairline, ink label.
struct SecondaryButtonStyle: ButtonStyle {
    var compact = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: compact ? Theme.Radius.control : Theme.Radius.control + 4,
                                     style: .continuous)
        configuration.label
            .font(.mono(compact ? .caption : .callout, weight: .semibold))
            .foregroundStyle(Theme.ink)
            .frame(maxWidth: compact ? nil : .infinity, minHeight: compact ? 32 : 50)
            .padding(.horizontal, compact ? Theme.Space.m : Theme.Space.l)
            .background(Theme.surfaceRaised.opacity(configuration.isPressed ? 0.7 : 1), in: shape)
            .overlay { shape.strokeBorder(Theme.hairline, lineWidth: 1) }
            .opacity(isEnabled ? 1 : 0.4)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.press, value: configuration.isPressed)
            .contentShape(Rectangle())
    }
}
