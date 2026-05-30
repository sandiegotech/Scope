import SwiftUI

struct PulseChart: View {
    let cpuValues: [Double]
    let memoryValues: [Double]
    let height: CGFloat

    init(cpuValues: [Double], memoryValues: [Double], height: CGFloat = 74) {
        self.cpuValues = cpuValues
        self.memoryValues = memoryValues
        self.height = height
    }

    var body: some View {
        Canvas { context, size in
            let gridColor = Color.secondary.opacity(0.16)
            let midY = size.height * 0.5

            var grid = Path()
            grid.move(to: CGPoint(x: 0, y: midY))
            grid.addLine(to: CGPoint(x: size.width, y: midY))
            context.stroke(grid, with: .color(gridColor), lineWidth: 1)

            context.stroke(
                path(for: memoryValues, in: size),
                with: .color(.teal),
                style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
            )

            context.stroke(
                path(for: cpuValues, in: size),
                with: .color(.orange),
                style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
            )
        }
        .frame(height: height)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.background.opacity(0.52))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.separator.opacity(0.35), lineWidth: 1)
        )
    }

    private func path(for values: [Double], in size: CGSize) -> Path {
        var path = Path()
        let visibleValues = values.isEmpty ? [0, 0] : values
        let step = visibleValues.count > 1 ? size.width / CGFloat(visibleValues.count - 1) : size.width

        for index in visibleValues.indices {
            let value = min(max(visibleValues[index], 0), 1)
            let point = CGPoint(
                x: CGFloat(index) * step,
                y: size.height - (CGFloat(value) * size.height)
            )

            if index == visibleValues.startIndex {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }

        return path
    }
}
