import AppKit
import SwiftUI

struct DashboardView: View {
    @Environment(\.openWindow) private var openWindow
    @ObservedObject var monitor: SystemMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            LazyVGrid(columns: moduleColumns, spacing: 8) {
                StatModule(
                    title: "CPU",
                    symbol: "cpu",
                    tint: .orange,
                    value: monitor.snapshot.cpu.primaryText,
                    progress: monitor.snapshot.cpu.usageRatio ?? 0,
                    lines: cpuLines
                )

                StatModule(
                    title: "MEMORY",
                    symbol: "memorychip",
                    tint: .teal,
                    value: monitor.snapshot.memory.primaryText,
                    progress: monitor.snapshot.memory.usedRatio,
                    lines: memoryLines
                )

                StatModule(
                    title: "BATTERY",
                    symbol: monitor.snapshot.battery.iconName,
                    tint: monitor.snapshot.battery.tint,
                    value: monitor.snapshot.battery.primaryText,
                    progress: monitor.snapshot.battery.chargeRatio ?? 0,
                    lines: batteryLines
                )

                StatModule(
                    title: "NETWORK",
                    symbol: "arrow.up.arrow.down",
                    tint: .cyan,
                    value: networkValue,
                    progress: nil,
                    lines: networkLines
                )

                StatModule(
                    title: "DISK",
                    symbol: "internaldrive",
                    tint: .indigo,
                    value: monitor.snapshot.disk.primaryText,
                    progress: monitor.snapshot.disk.usedRatio,
                    lines: diskLines
                )

                StatModule(
                    title: "HEALTH",
                    symbol: "gauge.with.dots.needle.67percent",
                    tint: healthTint,
                    value: healthValue,
                    progress: nil,
                    lines: healthLines
                )
            }

            ProcessTable(
                title: "CPU",
                tint: .orange,
                apps: Array(monitor.snapshot.topCPUApps.prefix(8)),
                primary: .cpu
            )

            ProcessTable(
                title: "MEMORY",
                tint: .teal,
                apps: Array(monitor.snapshot.topMemoryApps.prefix(8)),
                primary: .memory
            )

            footer
        }
        .padding(12)
        .background(.regularMaterial)
    }

    private var header: some View {
        HStack(spacing: 9) {
            Image(systemName: "opticaldiscdrive")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(
                    Circle()
                        .fill(LinearGradient(colors: [.teal, .indigo], startPoint: .topLeading, endPoint: .bottomTrailing))
                )

            VStack(alignment: .leading, spacing: 1) {
                Text("Disko")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                Text(monitor.isScanningDetails ? "Scanning" : monitor.snapshot.updatedAt.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                monitor.refresh(forceDeep: true)
            } label: {
                Image(systemName: "arrow.clockwise")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.borderless)
            .help("Refresh")
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button {
                openWindow(id: "details")
                NSApplication.shared.activate(ignoringOtherApps: true)
            } label: {
                Label("Details", systemImage: "macwindow")
            }
            .buttonStyle(.bordered)

            Spacer()

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "power")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.borderless)
            .help("Quit Disko")
        }
    }

    private var moduleColumns: [GridItem] {
        [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]
    }

    private var cpuLines: [ModuleLine] {
        [
            ModuleLine(label: "Cores", value: "\(monitor.snapshot.cpu.activeCoreCount)/\(monitor.snapshot.cpu.coreCount)"),
            ModuleLine(label: "Top", value: monitor.snapshot.topCPUApps.first.map { "\($0.name) \($0.cpuText)" } ?? "Quiet")
        ]
    }

    private var memoryLines: [ModuleLine] {
        [
            ModuleLine(label: "Used", value: monitor.snapshot.memory.usedBytes.byteString),
            ModuleLine(label: "Top", value: monitor.snapshot.topMemoryApps.first.map { "\($0.name) \($0.memoryText)" } ?? "Quiet")
        ]
    }

    private var batteryLines: [ModuleLine] {
        [
            ModuleLine(label: "State", value: monitor.snapshot.battery.stateText),
            ModuleLine(label: "Power", value: monitor.snapshot.battery.powerDrawText)
        ]
    }

    private var networkValue: String {
        "\(monitor.snapshot.network.downloadBytesPerSecond.rateString)"
    }

    private var networkLines: [ModuleLine] {
        [
            ModuleLine(label: "In", value: monitor.snapshot.network.downloadBytesPerSecond.rateString),
            ModuleLine(label: "Out", value: monitor.snapshot.network.uploadBytesPerSecond.rateString)
        ]
    }

    private var diskLines: [ModuleLine] {
        [
            ModuleLine(label: "Used", value: monitor.snapshot.disk.usedBytes.byteString),
            ModuleLine(label: "Total", value: monitor.snapshot.disk.totalBytes.byteString)
        ]
    }

    private var healthValue: String {
        if monitor.snapshot.sensors.thermalState != "Nominal" {
            return monitor.snapshot.sensors.thermalState
        }

        if monitor.snapshot.memory.usedRatio >= 0.85 {
            return "Memory"
        }

        if monitor.snapshot.disk.usedRatio >= 0.85 {
            return "Storage"
        }

        if monitor.snapshot.topPowerApp?.powerImpactText == "High" {
            return "App Load"
        }

        return "Steady"
    }

    private var healthTint: Color {
        switch healthValue {
        case "Steady":
            return .green
        case "Nominal":
            return .green
        case "Memory", "Storage", "App Load", "Fair":
            return .yellow
        default:
            return .orange
        }
    }

    private var healthLines: [ModuleLine] {
        [
            ModuleLine(label: "Thermal", value: monitor.snapshot.sensors.thermalState),
            ModuleLine(label: "Top", value: monitor.snapshot.topPowerApp?.name ?? "Quiet")
        ]
    }
}

private struct ModuleLine: Identifiable {
    var id: String { label }

    let label: String
    let value: String
}

private enum ProcessMetric {
    case cpu
    case memory
}

private struct StatModule: View {
    let title: String
    let symbol: String
    let tint: Color
    let value: String
    let progress: Double?
    let lines: [ModuleLine]

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 14)
                Text(title)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(value)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }

            if let progress {
                MeterBar(value: progress, tint: tint, height: 6)
            }

            VStack(spacing: 4) {
                ForEach(lines) { line in
                    HStack(spacing: 6) {
                        Text(line.label)
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 6)
                        Text(line.value)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .font(.system(size: 10, weight: .medium))
                }
            }
        }
        .padding(9)
        .frame(minHeight: 88, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.background.opacity(0.48))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.separator.opacity(0.28), lineWidth: 1)
        )
    }
}

private struct ProcessTable: View {
    let title: String
    let tint: Color
    let apps: [AppUsageMetric]
    let primary: ProcessMetric

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(primary == .cpu ? "CPU  MEM" : "MEM  CPU")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            if apps.isEmpty {
                Text("Quiet")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 5)
            } else {
                VStack(spacing: 3) {
                    ForEach(apps) { app in
                        ProcessRow(app: app, tint: tint, primary: primary)
                    }
                }
            }
        }
        .padding(9)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.background.opacity(0.48))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.separator.opacity(0.28), lineWidth: 1)
        )
    }
}

private struct ProcessRow: View {
    let app: AppUsageMetric
    let tint: Color
    let primary: ProcessMetric

    var body: some View {
        HStack(spacing: 8) {
            Text(app.name)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 8)

            Text(primaryValue)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(primaryColor)
                .monospacedDigit()
                .lineLimit(1)
                .frame(minWidth: 48, alignment: .trailing)

            Text(secondaryValue)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(secondaryColor)
                .monospacedDigit()
                .lineLimit(1)
                .frame(minWidth: 42, alignment: .trailing)
        }
    }

    private var primaryValue: String {
        primary == .cpu ? app.cpuText : app.memoryText
    }

    private var secondaryValue: String {
        primary == .cpu ? app.memoryText : app.cpuText
    }

    private var primaryColor: Color {
        primary == .cpu ? app.cpuPressureColor : app.memoryPressureColor
    }

    private var secondaryColor: Color {
        primary == .cpu ? app.memoryPressureColor : app.cpuPressureColor
    }
}

private struct MeterBar: View {
    let value: Double
    let tint: Color
    let height: CGFloat

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: height / 2, style: .continuous)
                    .fill(tint.opacity(0.18))
                RoundedRectangle(cornerRadius: height / 2, style: .continuous)
                    .fill(tint)
                    .frame(width: max(height, geometry.size.width * min(max(value, 0), 1)))
            }
        }
        .frame(height: height)
    }
}
