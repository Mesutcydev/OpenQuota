import SwiftUI

// Live mini-demos for each onboarding page. Every scene is a pure function
// of elapsed time `t` (see `Motion`), restarted when its page comes on screen.

// MARK: - 1 · Overview

struct OverviewScene: View {
    let t: Double

    private let rows: [(name: String, fraction: Double, value: String)] = [
        ("claude max", 0.64, "64%"),
        ("openrouter", 0.41, "$8.82"),
        ("mistral org", 0.26, "$127.60"),
        ("glm coding", 0.52, "52%"),
    ]

    var body: some View {
        let spend = 1766.34 * Motion.beat(t, from: 0.15, duration: 1.3)

        Panel(title: "spend · mtd") {
            VStack(alignment: .leading, spacing: 14) {
                Text(Format.currency(spend))
                    .font(.mono(size: 34, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.ink)
                    .contentTransition(.numericText(value: spend))

                VStack(spacing: 9) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                        let start = 0.45 + Double(index) * 0.16
                        HStack(spacing: 10) {
                            Text(row.name)
                                .foregroundStyle(Theme.inkSecondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            BlockBar(fraction: row.fraction * Motion.beat(t, from: start, duration: 0.9),
                                     cells: 10, font: .mono(.caption2))
                            Text(row.value)
                                .foregroundStyle(Theme.ink)
                                .frame(width: 64, alignment: .trailing)
                        }
                        .reveal(Motion.beat(t, from: start - 0.1, duration: 0.35))
                    }
                }
                .font(.mono(.caption))
                .monospacedDigit()
            }
            .padding(14)
        }
    }
}

// MARK: - 2 · Alerts

struct AlertsScene: View {
    let t: Double

    var body: some View {
        let used = 0.38 + 0.58 * Motion.beat(t, from: 0.35, duration: 2.4)
        let percent = Int((used * 100).rounded())
        let warn = Motion.beat(t, from: warnTime, duration: 0.3)
        let crit = Motion.beat(t, from: critTime, duration: 0.3)
        let banner = Motion.beat(t, from: critTime + 0.35, duration: 0.55)

        ZStack(alignment: .top) {
            Panel(title: "claude max · 5h window") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(percent)%")
                            .font(.mono(size: 40, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(Theme.severity(used, tint: Theme.ink))
                            .contentTransition(.numericText(value: Double(percent)))
                        Text("used")
                            .font(.mono(.footnote))
                            .foregroundStyle(Theme.inkSecondary)
                        Spacer()
                        Text("↻ 2h 14m")
                            .font(.mono(.caption))
                            .foregroundStyle(Theme.inkTertiary)
                    }
                    SegmentedMeter(fraction: used, height: 10, segment: 5, gap: 2)

                    VStack(alignment: .leading, spacing: 6) {
                        logLine("WARN", "crossed 75% · pace ok till reset", Theme.watch).reveal(warn)
                        logLine("CRIT", "crossed 90% · consider switching", Theme.critical).reveal(crit)
                    }
                    .frame(height: 44, alignment: .top)
                }
                .padding(14)
            }
            .padding(.top, 40)

            notification
                .opacity(banner)
                .offset(y: (1 - banner) * -40)
                .scaleEffect(0.94 + 0.06 * banner, anchor: .top)
        }
    }

    /// The meter climbs from 38% to 96% over 2.4 s; these are when it
    /// crosses the warning lines.
    private var warnTime: Double { crossing(0.75) }
    private var critTime: Double { crossing(0.90) }

    private func crossing(_ level: Double) -> Double {
        // Invert the ease-out: 1 - (1 - x)^3 = p  →  x = 1 - cbrt(1 - p).
        let p = (level - 0.38) / 0.58
        let x = 1 - cbrt(1 - p)
        return 0.35 + 2.4 * x
    }

    private func logLine(_ tag: String, _ text: String, _ color: Color) -> some View {
        HStack(spacing: 8) {
            Text(tag)
                .font(.mono(.caption2, weight: .bold))
                .foregroundStyle(color)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(color.opacity(0.13), in: RoundedRectangle(cornerRadius: 3))
            Text(text)
                .font(.mono(.caption2))
                .foregroundStyle(Theme.inkSecondary)
                .lineLimit(1)
        }
    }

    private var notification: some View {
        HStack(spacing: 10) {
            Text("❯")
                .font(.mono(size: 15, weight: .bold))
                .foregroundStyle(Theme.brand)
                .frame(width: 30, height: 30)
                .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text("openquota · now")
                    .font(.mono(.caption2, weight: .semibold))
                    .foregroundStyle(Theme.inkSecondary)
                Text("claude max is at 90% of its 5-hour window")
                    .font(.mono(.caption))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay { GlassRim(shape: RoundedRectangle(cornerRadius: 16, style: .continuous)) }
        .shadow(color: .black.opacity(0.12), radius: 14, y: 6)
        .padding(.horizontal, 6)
    }
}

// MARK: - 3 · Privacy

struct PrivacyScene: View {
    let t: Double

    private let command = "openquota connect openrouter"
    private let typeStart = 0.25
    private let perChar = 0.032
    private var typeEnd: Double { typeStart + Double(command.count) * perChar }

    var body: some View {
        let keyStart = typeEnd + 0.25
        let dots = Int(16 * Motion.progress(t, from: keyStart, duration: 0.45))
        let saved = keyStart + 0.7

        VStack(spacing: 18) {
            Image(systemName: t >= saved ? "lock.shield.fill" : "lock.shield")
                .font(.system(size: 46, weight: .regular))
                .foregroundStyle(t >= saved ? Theme.brand : Theme.inkTertiary)
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(.bounce, value: t >= saved)
                .frame(height: 56)

            Panel(title: "terminal") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 0) {
                        Text("$ ").foregroundStyle(Theme.brand)
                        Text(Motion.typed(command, t, from: typeStart, perChar: perChar))
                            .foregroundStyle(Theme.ink)
                        Text("▌")
                            .foregroundStyle(Theme.brand)
                            .opacity(t < keyStart && Motion.cursorOn(t, typing: t < typeEnd) ? 1 : 0)
                    }
                    HStack(spacing: 0) {
                        Text("› key: ").foregroundStyle(Theme.inkSecondary)
                        Text(String(repeating: "•", count: dots)).foregroundStyle(Theme.ink)
                    }
                    .reveal(Motion.beat(t, from: keyStart - 0.05, duration: 0.2))

                    status("ok", "saved to keychain · this iphone", Theme.brand)
                        .reveal(Motion.beat(t, from: saved, duration: 0.3))
                    status("ok", "sent only to openrouter.ai", Theme.brand)
                        .reveal(Motion.beat(t, from: saved + 0.3, duration: 0.3))
                    status("--", "openquota servers: none", Theme.inkTertiary)
                        .reveal(Motion.beat(t, from: saved + 0.6, duration: 0.3))
                }
                .font(.mono(.caption))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
            }
        }
    }

    private func status(_ tag: String, _ text: String, _ color: Color) -> some View {
        HStack(spacing: 6) {
            HStack(spacing: 0) {
                Text("[")
                Text(tag).foregroundStyle(color).fontWeight(.bold)
                Text("]")
            }
            .foregroundStyle(Theme.inkTertiary)
            Text(text).foregroundStyle(Theme.inkSecondary)
        }
    }
}

// MARK: - 4 · Glance

struct GlanceScene: View {
    let t: Double

    var body: some View {
        let expand = Motion.beat(t, from: 0.35, duration: 0.6)
        let first = Motion.beat(t, from: 0.9, duration: 0.55)
        let second = Motion.beat(t, from: 1.1, duration: 0.55)

        VStack(spacing: 28) {
            island(expand)
            HStack(spacing: 14) {
                creditsWidget.reveal(first, distance: 24)
                limitWidget(fill: 0.64 * Motion.beat(t, from: 1.3, duration: 0.8))
                    .reveal(second, distance: 24)
            }
        }
    }

    private func island(_ p: Double) -> some View {
        let width = 126 + (300 - 126) * p
        let height = 37 + (82 - 37) * p
        return ZStack {
            RoundedRectangle(cornerRadius: height / 2 * (1 - p) + 26 * p, style: .continuous)
                .fill(.black)
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("❯").foregroundStyle(.white)
                    Text("claude max").foregroundStyle(.white)
                    Spacer()
                    Text("64%").foregroundStyle(.white).fontWeight(.semibold)
                }
                .font(.mono(.caption))
                SegmentedMeter(fraction: 0.64, height: 6, segment: 4, gap: 2,
                               tint: Color(red: 0.89, green: 0.88, blue: 0.85), showsSeverity: false)
            }
            .padding(.horizontal, 18)
            .opacity(Motion.progress(p, from: 0.55, duration: 0.45))
        }
        .frame(width: width, height: height)
        .environment(\.colorScheme, .dark)
    }

    private var creditsWidget: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text("❯").foregroundStyle(Theme.brand)
                Text("openquota").foregroundStyle(Theme.inkSecondary)
            }
            .font(.mono(.caption2, weight: .bold))
            Spacer(minLength: 0)
            Text("$121.66")
                .font(.mono(size: 22, weight: .semibold))
                .foregroundStyle(Theme.ink)
            Text("credit left · 14 up")
                .font(.mono(size: 9))
                .foregroundStyle(Theme.inkSecondary)
        }
        .widgetTile()
    }

    private func limitWidget(fill: Double) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("claude max")
                .font(.mono(.caption, weight: .bold))
                .foregroundStyle(Theme.ink)
            Spacer(minLength: 0)
            Text("\(Int((fill * 100).rounded()))%")
                .font(.mono(size: 26, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Theme.ink)
            SegmentedMeter(fraction: fill, height: 5, segment: 3.5, gap: 1.5)
            Text("5-hour · ↻ 2h 14m")
                .font(.mono(size: 9))
                .foregroundStyle(Theme.inkSecondary)
        }
        .widgetTile()
    }
}

private extension View {
    /// Small home-screen widget mock.
    func widgetTile() -> some View {
        self
            .padding(14)
            .frame(width: 150, height: 150, alignment: .topLeading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay { GlassRim(shape: RoundedRectangle(cornerRadius: 24, style: .continuous)) }
            .shadow(color: .black.opacity(0.08), radius: 16, y: 8)
    }
}
