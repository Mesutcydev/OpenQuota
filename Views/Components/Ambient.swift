import SwiftUI

// MARK: - Ambient lights

/// Soft monochrome light drifting behind the Overview — pale haze on
/// graphite, faint shade on porcelain. No hue: colour in this app is kept for
/// warnings, so the backdrop only adds depth. A board that needs a look
/// brightens the haze slightly instead of tinting it.
///
/// Drawn with radial gradients rather than blurs (cheap to redraw), capped at
/// 30 fps, frozen under Reduce Motion, and dimmed in pure-black mode so the
/// OLED canvas stays mostly off.
struct AmbientLights: View {
    var mood: Theme.Level = .calm

    @Environment(\.colorScheme) private var scheme
    @Environment(\.oledBlack) private var oled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct Light {
        let color: Color
        /// Resting position as a fraction of the canvas.
        let anchor: UnitPoint
        /// Drift amplitude as a fraction of the canvas.
        let drift: CGSize
        /// Seconds per drift loop.
        let period: Double
        let phase: Double
        /// Radius as a fraction of the canvas width.
        let radius: CGFloat
    }

    private var palette: [Color] {
        let light = scheme == .dark ? Color.white : Color(hex: "15171A")
        return [light, light, light]
    }

    private var lights: [Light] {
        let c = palette
        return [
            Light(color: c[0], anchor: UnitPoint(x: 0.12, y: 0.06), drift: CGSize(width: 0.10, height: 0.05),
                  period: 19, phase: 0, radius: 0.95),
            Light(color: c[1], anchor: UnitPoint(x: 0.95, y: 0.30), drift: CGSize(width: 0.08, height: 0.08),
                  period: 23, phase: 1.7, radius: 0.85),
            Light(color: c[2], anchor: UnitPoint(x: 0.30, y: 0.85), drift: CGSize(width: 0.12, height: 0.06),
                  period: 29, phase: 3.1, radius: 1.0),
        ]
    }

    private var strength: Double {
        let base: Double = scheme == .light ? 0.045 : (oled ? 0.035 : 0.06)
        switch mood {
        case .calm: return base
        case .watch: return base * 1.2
        case .critical: return base * 1.4
        }
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                for light in lights {
                    let angle = (t / light.period) * 2 * .pi + light.phase
                    let center = CGPoint(
                        x: (light.anchor.x + light.drift.width * sin(angle)) * size.width,
                        y: (light.anchor.y + light.drift.height * cos(angle * 0.8)) * size.height)
                    // Slow breathing so the lights feel alive, not just moving.
                    let breathe = 0.85 + 0.15 * sin(angle * 1.3)
                    let radius = light.radius * size.width
                    let gradient = Gradient(stops: [
                        .init(color: light.color.opacity(strength * breathe), location: 0),
                        .init(color: light.color.opacity(strength * breathe * 0.35), location: 0.45),
                        .init(color: light.color.opacity(0), location: 1),
                    ])
                    ctx.fill(
                        Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius,
                                               width: radius * 2, height: radius * 2)),
                        with: .radialGradient(gradient, center: center, startRadius: 0, endRadius: radius))
                }
            }
        }
        .animation(.easeInOut(duration: 1.2), value: mood)
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Live accents

/// Terminal cursor that blinks like a real prompt.
struct BlinkingCursor: View {
    var text = "▌"
    var color: Color = Theme.brand

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.53)) { context in
            let on = reduceMotion || Int(context.date.timeIntervalSinceReferenceDate / 0.53).isMultiple(of: 2)
            Text(text)
                .foregroundStyle(color)
                .opacity(on ? 1 : 0.15)
                .animation(.easeInOut(duration: 0.12), value: on)
        }
        .accessibilityHidden(true)
    }
}

/// Status LED: a dot that breathes and casts a little glow.
struct PulseDot: View {
    var color: Color
    var size: CGFloat = 7
    /// Seconds per breath; faster reads as more urgent.
    var period: Double = 2.4

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var lit = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .background {
                Circle()
                    .fill(color.opacity(0.55))
                    .scaleEffect(lit ? 2.4 : 1)
                    .opacity(lit ? 0 : 0.8)
            }
            .shadow(color: color.opacity(lit ? 0.9 : 0.35), radius: lit ? 4 : 1.5)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: period / 2).repeatForever(autoreverses: true)) { lit = true }
            }
            .accessibilityHidden(true)
    }
}

/// "syncing" with dots that tick along.
struct SyncingLabel: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.35)) { context in
            let n = Int(context.date.timeIntervalSinceReferenceDate / 0.35) % 4
            Text("syncing" + String(repeating: ".", count: n) + String(repeating: " ", count: 3 - n))
        }
    }
}

// MARK: - Light on cards

/// A thin highlight that travels around a card's edge, like light catching
/// a bevel. One slow lap every `period` seconds.
struct RunningRim<S: InsettableShape>: View {
    let shape: S
    var color: Color = Theme.brand
    var period: Double = 7

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let angle = Angle.degrees((t / period).truncatingRemainder(dividingBy: 1) * 360)
            let peak = scheme == .dark ? 0.55 : 0.35
            let gradient = AngularGradient(
                stops: [
                    .init(color: color.opacity(0), location: 0),
                    .init(color: color.opacity(0), location: 0.78),
                    .init(color: color.opacity(peak), location: 0.92),
                    .init(color: color.opacity(0), location: 1),
                ],
                center: .center, angle: angle)
            ZStack {
                shape.strokeBorder(gradient, lineWidth: 1)
                shape.strokeBorder(gradient, lineWidth: 3).blur(radius: 4).opacity(0.7)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// A soft diagonal sheen that sweeps across the content now and then.
struct LightSweep: ViewModifier {
    var interval: Double = 6
    var duration: Double = 1.4
    var radius: CGFloat = Theme.Radius.card

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.overlay {
            if !reduceMotion {
                TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
                    let t = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: interval)
                    let p = min(t / duration, 1)
                    GeometryReader { proxy in
                        let w = proxy.size.width
                        LinearGradient(
                            colors: [.white.opacity(0), .white.opacity(scheme == .dark ? 0.07 : 0.35), .white.opacity(0)],
                            startPoint: .leading, endPoint: .trailing)
                            .frame(width: w * 0.45)
                            .rotationEffect(.degrees(18))
                            .offset(x: -w * 0.6 + p * w * 1.7)
                            .opacity(p < 1 ? 1 : 0)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
                .blendMode(scheme == .dark ? .plusLighter : .softLight)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
    }
}

extension View {
    func lightSweep(every interval: Double = 6) -> some View {
        modifier(LightSweep(interval: interval))
    }

    func runningRim(radius: CGFloat = Theme.Radius.card, color: Color = Theme.brand, period: Double = 7) -> some View {
        overlay { RunningRim(shape: RoundedRectangle(cornerRadius: radius, style: .continuous), color: color, period: period) }
    }
}

// MARK: - Animated gauge

/// `BlockBar` that fills up from empty when it first appears, then follows
/// changes cell by cell.
struct LiveBlockBar: View {
    let fraction: Double
    var cells = 10
    var font: Font = .mono(.caption2)
    var showsSeverity = true
    var delay: Double = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown: Double = 0

    var body: some View {
        BlockBar(fraction: shown, cells: cells, font: font, showsSeverity: showsSeverity)
            .onAppear { fill(to: fraction, delay: delay) }
            .onChange(of: fraction) { _, value in fill(to: value, delay: 0) }
    }

    /// Steps the visible cell count so the text bar ticks up like a loader.
    private func fill(to target: Double, delay: Double) {
        guard !reduceMotion else { shown = target; return }
        let start = shown
        let steps = max(Int(abs(target - start) * Double(cells)), 1)
        for i in 1...steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay + Double(i) * 0.045) {
                shown = start + (target - start) * Double(i) / Double(steps)
            }
        }
    }
}
