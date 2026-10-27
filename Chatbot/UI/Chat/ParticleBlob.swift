import SwiftUI

/// The dotted, slowly deforming sphere from voice mode. `level` (0…1) makes it swell with
/// your voice; `energy` sets how lively it is when no one is talking.
struct ParticleBlob: View {
    var level: Double
    var energy: Double = 0.4

    private static let points = fibonacciSphere(count: 1100)
    private static let palette: [Color] = (0..<16).map { i in
        let t = Double(i) / 15
        return Color(red: 0.96 - 0.34 * t, green: 0.47 - 0.23 * t, blue: 0.62 + 0.33 * t)
    }

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                Self.draw(in: &context, size: size, time: t, level: level, energy: energy)
            }
        }
        .drawingGroup()
        .accessibilityHidden(true)
    }

    private static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, level: Double, energy: Double) {
        let radius: Double = Double(min(size.width, size.height)) * 0.34
        let originX: Double = Double(size.width) / 2
        let originY: Double = Double(size.height) / 2
        let speed: Double = 0.6 + energy
        let amplitude: Double = 0.10 + energy * 0.08 + level * 0.35
        let spinY: Double = t * 0.35 * speed
        let tiltX: Double = sin(t * 0.21) * 0.5
        let sinY = sin(spinY), cosY = cos(spinY)
        let sinX = sin(tiltX), cosX = cos(tiltX)

        for p in points {
            // Smooth pseudo-noise pushes each point in or out along its normal.
            let a: Double = sin(p.x * 3.1 + t * 1.3 * speed)
            let b: Double = cos(p.y * 2.7 - t * 0.9 * speed)
            let c: Double = sin(p.z * 3.7 + t * 0.7 * speed)
            let scale: Double = 1 + (a * b + 0.5 * c) * amplitude
            var x: Double = p.x * scale
            var y: Double = p.y * scale
            var z: Double = p.z * scale

            // Rotate around Y, then tilt around X.
            let x1: Double = x * cosY + z * sinY
            let z1: Double = z * cosY - x * sinY
            x = x1
            z = z1
            let y2: Double = y * cosX - z * sinX
            let z2: Double = y * sinX + z * cosX
            y = y2
            z = z2

            let depth: Double = (z + 1.5) / 3 // 0 at the back, 1 at the front
            let dot: Double = 0.9 + depth * 1.9
            let colorIndex = min(15, max(0, Int((y + 1.2) / 2.4 * 15)))
            let rect = CGRect(x: originX + x * radius - dot / 2, y: originY + y * radius - dot / 2, width: dot, height: dot)
            context.fill(Path(ellipseIn: rect), with: .color(palette[colorIndex].opacity(0.18 + depth * 0.82)))
        }
    }

    private struct Point3 {
        var x: Double, y: Double, z: Double
    }

    private static func fibonacciSphere(count: Int) -> [Point3] {
        let golden = Double.pi * (3 - 5.0.squareRoot())
        return (0..<count).map { i in
            let y = 1 - (Double(i) / Double(count - 1)) * 2
            let r = (1 - y * y).squareRoot()
            let theta = golden * Double(i)
            return Point3(x: cos(theta) * r, y: y, z: sin(theta) * r)
        }
    }
}
