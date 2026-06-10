import SwiftUI

struct MenuBarLoadView: View {
    let cpu: Double
    let memory: Double

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "internaldrive.fill")
            VStack(spacing: 2) {
                MiniLoadBar(value: cpu, color: .orange)
                MiniLoadBar(value: memory, color: .teal)
            }
        }
        .help("Scope CPU and memory")
    }
}

private struct MiniLoadBar: View {
    let value: Double
    let color: Color

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(color.opacity(0.24))
                Capsule()
                    .fill(color)
                    .frame(width: max(2, geometry.size.width * min(max(value, 0), 1)))
            }
        }
        .frame(width: 18, height: 3)
    }
}
