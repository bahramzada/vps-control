import SwiftUI

struct Sparkline: View {
    let values: [Double]
    var color: Color = VPSTheme.green

    private var normalizedPoints: [CGPoint] {
        guard values.count > 1,
              let minimum = values.min(),
              let maximum = values.max()
        else {
            return []
        }
        let range = max(maximum - minimum, 0.001)
        return values.enumerated().map { index, value in
            CGPoint(
                x: Double(index) / Double(values.count - 1),
                y: 1 - ((value - minimum) / range)
            )
        }
    }

    var body: some View {
        Canvas { context, size in
            let points = normalizedPoints.map {
                CGPoint(x: $0.x * size.width, y: $0.y * max(size.height - 4, 1) + 2)
            }
            guard let first = points.first else {
                var baseline = Path()
                baseline.move(to: CGPoint(x: 0, y: size.height / 2))
                baseline.addLine(to: CGPoint(x: size.width, y: size.height / 2))
                context.stroke(baseline, with: .color(color.opacity(0.55)), lineWidth: 1)
                return
            }

            var area = Path()
            area.move(to: CGPoint(x: first.x, y: size.height))
            area.addLine(to: first)
            for point in points.dropFirst() {
                area.addLine(to: point)
            }
            if let last = points.last {
                area.addLine(to: CGPoint(x: last.x, y: size.height))
            }
            area.closeSubpath()
            context.fill(
                area,
                with: .linearGradient(
                    Gradient(colors: [color.opacity(0.30), color.opacity(0.01)]),
                    startPoint: CGPoint(x: 0, y: 0),
                    endPoint: CGPoint(x: 0, y: size.height)
                )
            )

            var line = Path()
            line.move(to: first)
            for point in points.dropFirst() {
                line.addLine(to: point)
            }
            context.stroke(line, with: .color(color), lineWidth: 1.35)
        }
        .accessibilityHidden(true)
    }
}
