import SwiftUI

/// Planar adaptation of Wisdome's facial shader at orbi-github commit 8406510.
/// The full surface is the head; facial features retain the source sampling grid.
struct OrbiFace: View {
    let phase: OrbiPhase
    let wakeProgress: Double
    @State private var phaseStarted = Date()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let gold = RGB(1, 0.7664, 0.0812)
    private let red = RGB(0.96, 0.09, 0.035)
    private let ink = RGB(0.075, 0.052, 0.12)
    private let cell = 1.15

    var body: some View {
        TimelineView(.animation(minimumInterval: phase == .sleeping ? 0.2 : 1.0 / 15,
                                paused: reduceMotion)) { context in
            let time = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
            let cooling = phase == .returningToSleep
                ? min(1, max(0, context.date.timeIntervalSince(phaseStarted) / 4.5)) : 0
            let wake = phase == .sleeping ? 0 : (phase == .waking ? wakeProgress : 1 - cooling)
            let brightness = 0.018 + 0.982 * wake
            let surface = phase.isPerforming
                ? red.mix(gold, cooling).scaled(brightness)
                : gold.scaled(brightness)
            Canvas { graphics, size in
                graphics.fill(Path(CGRect(origin: .zero, size: size)), with: .color(surface.color))
                let scale = min(size.width / 60, size.height / 65)
                let snore = (sin(time * 1.6) + 1) / 2
                let shake = phase == .angry && !reduceMotion ? sin(time * 22) * 0.6 : 0
                let center = CGPoint(x: size.width / 2 + shake * scale, y: size.height * 0.47)
                let blinkPhase = time.truncatingRemainder(dividingBy: 3.1)
                let blink = blinkPhase < 0.16 ? 1 - sin(blinkPhase / 0.16 * .pi) : 1
                let breath = 1 + (phase == .sleeping ? 0.006 : 0.017) * sin(time * 1.6)
                for row in -24...24 {
                    for column in -26...26 {
                        let qx = (Double(column) + 0.5) * cell
                        let qy = (Double(row) + 0.5) * cell
                        let color = sample(x: qx, y: qy, wake: wake, blink: blink,
                                           time: time, snore: snore, surface: surface)
                        let unit = scale * breath
                        let rect = CGRect(x: center.x + Double(column) * cell * unit,
                                          y: center.y - Double(row + 1) * cell * unit,
                                          width: cell * unit + 0.1, height: cell * unit + 0.1)
                        graphics.fill(Path(rect), with: .color(color.color))
                    }
                }
                if phase == .shushing { drawFinger(in: &graphics, center: center, scale: scale) }
                if wake < 0.15 { drawSnore(in: &graphics, size: size, time: time, wake: wake) }
            }
        }
        .onChange(of: phase) { _, _ in phaseStarted = Date() }
        .accessibilityLabel(accessibilityDescription)
    }

    private var accessibilityDescription: String {
        switch phase {
        case .sleeping: return "Orbi sleeping quietly"
        case .waking: return "Orbi slowly waking up"
        case .angry: return "Orbi is red and angry"
        case .shushing: return "Orbi asking for silence"
        case .returningToSleep: return "Orbi going back to sleep"
        }
    }

    private func sample(x: Double, y: Double, wake: Double, blink: Double,
                        time: Double, snore: Double, surface: RGB) -> RGB {
        var color = surface
        let sleepyInk = RGB(0.10, 0.075, 0.025)
        let detailVisibility = 0.075 + 0.925 * wake
        let angry = phase == .angry || phase == .shushing
        let expression = angry ? 0.52 : 0.04 + 0.96 * wake
        for side in [-1.0, 1.0] {
            let ex = x - side * 14
            let ey = y - 4.4
            if wake < 0.08 {
                if abs(ex) < 7 && abs(ey + 0.025 * ex * ex) < 0.55 { color = sleepyInk }
                continue
            }
            let height = max(0.32, 10.4 * expression * blink)
            let eye = ellipse(ex, ey, 8.6, height) < 0
            let contact = exp(-max(ellipse(ex - 0.25, ey + 0.3, 8.8, height + 0.3), 0) * 1.8)
            color = color.mix(ink, contact * 0.11 * wake)
            if eye {
                color = surface.mix(RGB(1, 0.92, 0.74), detailVisibility)
                let gx = sin(time * 0.71) * 0.12 * 3.2
                let gy = sin(time * 0.49) * 0.07 * 2.5
                if ellipse(ex - gx, ey - gy, 5.4, min(6.8, max(0.2, height * 0.78))) < 0 {
                    color = RGB(0.13, 0.075, 0.095)
                    if ellipse(ex - gx + 1, ey - gy - 1.4, 1.4, min(1.4, height * 0.3)) < 0 {
                        color = surface.mix(RGB(1, 0.99, 1), wake)
                    }
                }
                if ey > height * 0.86 { color = surface }
            }
            let bx = min(7, max(-7, ex))
            let arch = 0.85 * (1 - pow(bx / 7.4, 2))
            let tilt = angry ? 1.2 : 0
            let browY = 16.6 + (angry ? -0.5 : 0) * 1.35
            if hypot(ex - bx, y - browY - arch - side * tilt * 0.32 * bx) < 0.92 {
                color = surface.mix(ink, wake)
            }
        }
        let opening: Double
        let width: Double
        let smile: Double
        switch phase {
        case .angry:
            opening = 0.65 + 0.18 * abs(sin(time * 11))
            width = 11.6
            smile = -0.45
        case .shushing:
            opening = 0.9
            width = 4.6
            smile = 0
        case .sleeping:
            opening = 0.04 + snore * 0.09
            width = 2.8
            smile = 0
        case .waking, .returningToSleep:
            opening = 0.025 + (1 - wake) * snore * 0.06
            width = 3 + 5.8 * wake
            smile = 0.55 * wake
        }
        let curve = smile * (4.3 * pow(x / width, 2) - 1.8)
        let mouthY = y + 8.5 - curve
        let mouthHeight = 0.48 + opening * 5
        if ellipse(x, mouthY, width, mouthHeight) < 0 {
            color = wake < 0.08 ? sleepyInk : surface.mix(ink, detailVisibility)
            if phase == .angry {
                if abs(x) < width * 0.83 && abs(mouthY - mouthHeight * 0.64) < 0.38 + opening * 0.5 {
                    color = RGB(1, 0.98, 0.88)
                }
                if ellipse(x, mouthY + mouthHeight * 0.73, width * 0.56, mouthHeight * 0.32) < 0 {
                    color = RGB(1, 0.27, 0.36)
                }
            }
        }
        return color
    }

    private func ellipse(_ x: Double, _ y: Double, _ rx: Double, _ ry: Double) -> Double {
        (hypot(x / rx, y / ry) - 1) * min(rx, ry)
    }

    private func drawSnore(in graphics: inout GraphicsContext, size: CGSize, time: Double, wake: Double) {
        for index in 0..<3 {
            let phase = (time * 0.22 + Double(index) / 3).truncatingRemainder(dividingBy: 1)
            let opacity = (1 - phase) * 0.14 * (1 - wake)
            let text = Text(index == 0 ? "z" : "Z")
                .font(.system(size: 9 + CGFloat(index) * 2, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(opacity))
            graphics.draw(text, at: CGPoint(x: size.width * 0.75 + phase * 12,
                                           y: size.height * 0.45 - phase * 45))
        }
    }

    private func drawFinger(in graphics: inout GraphicsContext, center: CGPoint, scale: Double) {
        for row in -32 ... -4 {
            for column in -4...9 {
                let x = Double(column) * cell
                let y = Double(row) * cell
                let finger = abs(x) < 2.8 && y > -28 && y < -5
                let hand = x > -2.8 && x < 9 && y > -34 && y < -24
                guard finger || hand else { continue }
                let edge = finger && (abs(x) > 1.8 || y > -6.5)
                    || hand && (x > 7.5 || y < -32.5)
                let color = edge ? ink : RGB(1, 0.86, 0.34)
                let rect = CGRect(x: center.x + x * scale, y: center.y - (y + cell) * scale,
                                  width: cell * scale + 0.1, height: cell * scale + 0.1)
                graphics.fill(Path(rect), with: .color(color.color))
            }
        }
    }
}

private struct RGB {
    var r: Double
    var g: Double
    var b: Double

    init(_ r: Double, _ g: Double, _ b: Double) { self.r = r; self.g = g; self.b = b }
    var color: Color { Color(.sRGB, red: r, green: g, blue: b, opacity: 1) }
    func scaled(_ amount: Double) -> RGB { RGB(r * amount, g * amount, b * amount) }
    func mix(_ other: RGB, _ amount: Double) -> RGB {
        RGB(r + (other.r - r) * amount, g + (other.g - g) * amount, b + (other.b - b) * amount)
    }
}
