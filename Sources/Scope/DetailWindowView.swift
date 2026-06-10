import AppKit
import SwiftUI

struct DetailWindowView: View {
    @ObservedObject var monitor: SystemMonitor
    @StateObject private var gitHubSync = GitHubSyncMonitor()
    @State private var section: DetailSection = .apps

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            sectionPicker
            Divider()

            ScrollView {
                content
                    .padding(18)
            }
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(minWidth: 820, minHeight: 580)
        .onAppear {
            monitor.refresh(forceDeep: monitor.snapshot.storageAnalysis.scannedFileCount == 0)
        }
        .onChange(of: section) { newSection in
            if newSection == .github && gitHubSync.repos.isEmpty {
                gitHubSync.refresh()
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 1) {
                Text("Scope")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                Text(monitor.isScanningDetails ? "Scanning storage, apps, and network..." : monitor.snapshot.updatedText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                monitor.refresh(forceDeep: true)
            } label: {
                Image(systemName: monitor.isScanningDetails ? "clock" : "arrow.clockwise")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.borderless)
            .disabled(monitor.isScanningDetails)
            .help("Refresh")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    private var sectionPicker: some View {
        Picker("Section", selection: $section) {
            ForEach(DetailSection.allCases) { item in
                Label(item.rawValue, systemImage: item.symbol)
                    .tag(item)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var content: some View {
        switch section {
        case .overview:
            overview
        case .power:
            power
        case .storage:
            storage
        case .apps:
            apps
        case .network:
            network
        case .health:
            health
        case .github:
            github
        }
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: 18) {
            PulseChart(
                cpuValues: monitor.snapshot.cpuHistory,
                memoryValues: monitor.snapshot.memoryHistory,
                height: 150
            )

            LazyVGrid(columns: detailColumns, spacing: 12) {
                DetailMetricCard(
                    icon: "gauge.with.dots.needle.67percent",
                    tint: healthTint,
                    title: "Health",
                    value: healthValue,
                    detail: healthDetail,
                    progress: nil
                )

                DetailMetricCard(
                    icon: "cpu",
                    tint: .orange,
                    title: "CPU",
                    value: monitor.snapshot.cpu.primaryText,
                    detail: "General compute • \(monitor.snapshot.cpu.detailText)",
                    progress: monitor.snapshot.cpu.usageRatio
                )

                DetailMetricCard(
                    icon: "memorychip",
                    tint: .teal,
                    title: "Memory",
                    value: monitor.snapshot.memory.primaryText,
                    detail: monitor.snapshot.memory.detailText,
                    progress: monitor.snapshot.memory.usedRatio
                )

                DetailMetricCard(
                    icon: "internaldrive",
                    tint: .indigo,
                    title: "Storage",
                    value: monitor.snapshot.disk.primaryText,
                    detail: monitor.snapshot.disk.detailText,
                    progress: monitor.snapshot.disk.usedRatio
                )
            }

            HStack(alignment: .top, spacing: 18) {
                SectionBlock(title: "System Signals", symbol: "gauge.with.dots.needle.67percent") {
                    VStack(spacing: 8) {
                        PlainInfoRow(title: "CPU", value: monitor.snapshot.cpu.primaryText, detail: "General-purpose app and system work")
                        PlainInfoRow(title: "Memory", value: monitor.snapshot.memory.primaryText, detail: monitor.snapshot.memory.detailText)
                        PlainInfoRow(title: "Thermal", value: monitor.snapshot.sensors.thermalState, detail: monitor.snapshot.sensors.thermalDetail)
                    }
                }

                SectionBlock(title: "Apps Pulling Most", symbol: "bolt.horizontal") {
                    if monitor.snapshot.topApps.isEmpty {
                        EmptyState(text: "No significant app pull detected.")
                    } else {
                        VStack(spacing: 8) {
                            ForEach(monitor.snapshot.topPowerApps.prefix(6)) { app in
                                PowerUsageRow(app: app)
                            }
                        }
                    }
                }
            }

            HStack(alignment: .top, spacing: 18) {
                SectionBlock(title: "Storage Candidates", symbol: "folder.badge.minus") {
                    if monitor.snapshot.storageCandidates.isEmpty {
                        EmptyState(text: "No large stale files found in the first scan.")
                    } else {
                        VStack(spacing: 8) {
                            ForEach(monitor.snapshot.storageCandidates.prefix(6)) { item in
                                StorageCandidateRow(item: item)
                            }
                        }
                    }
                }
            }
        }
    }

    private var power: some View {
        VStack(alignment: .leading, spacing: 16) {
            LazyVGrid(columns: detailColumns, spacing: 12) {
                DetailMetricCard(
                    icon: monitor.snapshot.battery.iconName,
                    tint: monitor.snapshot.battery.tint,
                    title: "Battery",
                    value: monitor.snapshot.battery.primaryText,
                    detail: monitor.snapshot.battery.detailText,
                    progress: monitor.snapshot.battery.chargeRatio
                )

                DetailMetricCard(
                    icon: "powerplug",
                    tint: .green,
                    title: "Power State",
                    value: monitor.snapshot.battery.stateText,
                    detail: monitor.snapshot.battery.adapterText,
                    progress: nil
                )

                DetailMetricCard(
                    icon: "bolt.horizontal",
                    tint: .yellow,
                    title: "Power Draw",
                    value: monitor.snapshot.battery.powerDrawText,
                    detail: "Battery registry and adapter data when available",
                    progress: nil
                )

                DetailMetricCard(
                    icon: "leaf",
                    tint: monitor.snapshot.sensors.lowPowerMode ? .green : .secondary,
                    title: "Power Mode",
                    value: monitor.snapshot.sensors.lowPowerMode ? "Low Power" : "Standard",
                    detail: monitor.snapshot.sensors.lowPowerMode ? "macOS is reducing energy use" : "Normal performance mode",
                    progress: nil
                )

            }

            SectionBlock(title: "Apps Pulling Most", symbol: "bolt.horizontal") {
                if monitor.snapshot.topApps.isEmpty {
                    EmptyState(text: "No significant CPU or memory pull detected.")
                } else {
                    VStack(spacing: 8) {
                        ForEach(monitor.snapshot.topPowerApps) { app in
                            PowerUsageRow(app: app)
                        }
                    }
                }
            }

            SectionBlock(title: "Battery Details", symbol: monitor.snapshot.battery.iconName) {
                VStack(spacing: 8) {
                    PlainInfoRow(title: "Charge", value: monitor.snapshot.battery.primaryText, detail: monitor.snapshot.battery.detailText)
                    PlainInfoRow(title: "Power", value: monitor.snapshot.battery.powerDrawText, detail: monitor.snapshot.battery.adapterText)
                    PlainInfoRow(title: "Health", value: monitor.snapshot.battery.healthText, detail: monitor.snapshot.battery.levelRatio == nil ? "No internal battery reported" : "Reported by macOS power sources and battery registry")
                }
            }
        }
    }

    private var storage: some View {
        VStack(alignment: .leading, spacing: 16) {
            LazyVGrid(columns: detailColumns, spacing: 12) {
                DetailMetricCard(
                    icon: "internaldrive",
                    tint: .indigo,
                    title: "Volume",
                    value: monitor.snapshot.disk.primaryText,
                    detail: monitor.snapshot.disk.detailText,
                    progress: monitor.snapshot.disk.usedRatio
                )

                DetailMetricCard(
                    icon: "folder.badge.minus",
                    tint: .teal,
                    title: "Reviewable",
                    value: monitor.snapshot.storageAnalysis.reviewBytes.byteString,
                    detail: "\(monitor.snapshot.storageAnalysis.categories.count) categories",
                    progress: nil
                )

                DetailMetricCard(
                    icon: "doc.text.magnifyingglass",
                    tint: .orange,
                    title: "Scanned",
                    value: monitor.snapshot.storageAnalysis.scannedText,
                    detail: monitor.snapshot.storageAnalysis.scannedBytes.byteString,
                    progress: nil
                )

                DetailMetricCard(
                    icon: "folder",
                    tint: .pink,
                    title: "Hotspots",
                    value: "\(monitor.snapshot.storageAnalysis.folderHotspots.count)",
                    detail: "Large or file-heavy folders",
                    progress: nil
                )
            }

            SectionBlock(title: "Cleanup Categories", symbol: "square.grid.2x2") {
                if monitor.snapshot.storageAnalysis.categories.isEmpty {
                    EmptyState(text: monitor.isScanningDetails ? "Scanning..." : "No storage categories yet.")
                } else {
                    VStack(spacing: 8) {
                        ForEach(monitor.snapshot.storageAnalysis.categories) { category in
                            StorageCategoryRow(category: category)
                        }
                    }
                }
            }

            SectionBlock(title: "Folder Hotspots", symbol: "folder.badge.questionmark") {
                if monitor.snapshot.storageAnalysis.folderHotspots.isEmpty {
                    EmptyState(text: monitor.isScanningDetails ? "Scanning..." : "No large folder hotspots found.")
                } else {
                    VStack(spacing: 8) {
                        ForEach(monitor.snapshot.storageAnalysis.folderHotspots) { folder in
                            StorageFolderRow(folder: folder)
                        }
                    }
                }
            }

            SectionBlock(title: "Stale Large Files", symbol: "doc.text.magnifyingglass") {
                if monitor.snapshot.storageAnalysis.staleFiles.isEmpty {
                    EmptyState(text: monitor.isScanningDetails ? "Scanning..." : "No stale large files found.")
                } else {
                    VStack(spacing: 8) {
                        ForEach(monitor.snapshot.storageAnalysis.staleFiles) { item in
                            StorageCandidateRow(item: item)
                        }
                    }
                }
            }
        }
    }

    private var apps: some View {
        VStack(alignment: .leading, spacing: 16) {
            LazyVGrid(columns: detailColumns, spacing: 12) {
                DetailMetricCard(
                    icon: "macwindow",
                    tint: .indigo,
                    title: "Visible",
                    value: "\(monitor.snapshot.visibleApps.count)",
                    detail: "Open app processes",
                    progress: nil
                )

                DetailMetricCard(
                    icon: "gearshape.2",
                    tint: .orange,
                    title: "Background",
                    value: "\(monitor.snapshot.backgroundApps.count)",
                    detail: "Relevant background processes",
                    progress: nil
                )

                DetailMetricCard(
                    icon: "cpu",
                    tint: .orange,
                    title: "Top CPU",
                    value: monitor.snapshot.topCPUApps.first?.name ?? "Quiet",
                    detail: monitor.snapshot.topCPUApps.first?.cpuDetailText ?? "-",
                    progress: nil
                )

                DetailMetricCard(
                    icon: "memorychip",
                    tint: .teal,
                    title: "Top Memory",
                    value: monitor.snapshot.topMemoryApps.first?.name ?? "Quiet",
                    detail: monitor.snapshot.topMemoryApps.first?.memoryDetailText ?? "-",
                    progress: nil
                )
            }

            SectionBlock(title: "Usage Window", symbol: "clock.arrow.circlepath") {
                let histories = appUsageWindowHistories

                if histories.isEmpty {
                    EmptyState(text: monitor.isScanningDetails ? "Collecting..." : "Usage history will appear after the next app scan.")
                } else {
                    VStack(spacing: 8) {
                        ForEach(histories.prefix(8)) { history in
                            AppUsageWindowRow(history: history)
                        }
                    }
                }
            }

            AppImpactSection(
                title: "Visible Tasks",
                symbol: "macwindow",
                apps: monitor.snapshot.visibleApps,
                histories: monitor.appHistories,
                emptyText: monitor.isScanningDetails ? "Scanning..." : "No visible apps found"
            )

            AppImpactSection(
                title: "Background Tasks",
                symbol: "gearshape.2",
                apps: Array(monitor.snapshot.backgroundApps.prefix(48)),
                histories: monitor.appHistories,
                emptyText: monitor.isScanningDetails ? "Scanning..." : "No relevant background activity"
            )

            AppImpactSection(
                title: "Network Activity",
                symbol: "point.3.connected.trianglepath.dotted",
                apps: Array(monitor.snapshot.networkActiveApps.prefix(24)),
                histories: monitor.appHistories,
                emptyText: monitor.isScanningDetails ? "Scanning..." : "No app network connections"
            )

            AppImpactSection(
                title: "File / System Access",
                symbol: "externaldrive.connected.to.line.below",
                apps: Array(monitor.snapshot.systemAccessApps.prefix(36)),
                histories: monitor.appHistories,
                emptyText: monitor.isScanningDetails ? "Scanning..." : "No notable file or system access"
            )
        }
    }

    private var network: some View {
        VStack(alignment: .leading, spacing: 16) {
            LazyVGrid(columns: detailColumns, spacing: 12) {
                DetailMetricCard(
                    icon: "arrow.up.arrow.down.circle",
                    tint: .blue,
                    title: "Total Data",
                    value: monitor.snapshot.network.totalText,
                    detail: monitor.snapshot.network.totalDetailText,
                    progress: nil
                )

                DetailMetricCard(
                    icon: "arrow.down",
                    tint: .cyan,
                    title: "Downloaded",
                    value: monitor.snapshot.network.totalReceivedBytes.byteString,
                    detail: "Now \(monitor.snapshot.network.downloadBytesPerSecond.rateString)",
                    progress: nil
                )

                DetailMetricCard(
                    icon: "arrow.up",
                    tint: .orange,
                    title: "Uploaded",
                    value: monitor.snapshot.network.totalSentBytes.byteString,
                    detail: "Now \(monitor.snapshot.network.uploadBytesPerSecond.rateString)",
                    progress: nil
                )

                DetailMetricCard(
                    icon: "app.connected.to.app.below.fill",
                    tint: .indigo,
                    title: "Top App Data",
                    value: monitor.snapshot.networkDataApps.first?.name ?? "Quiet",
                    detail: monitor.snapshot.networkDataApps.first.map { "\($0.networkTotalText) total • \($0.networkText) now" } ?? "No app transfer reported",
                    progress: nil
                )
            }

            SectionBlock(title: "App Data Use", symbol: "app.connected.to.app.below.fill") {
                let apps = Array(monitor.snapshot.networkDataApps.prefix(32))

                if apps.isEmpty {
                    EmptyState(text: monitor.isScanningDetails ? "Scanning..." : "No app network data reported.")
                } else {
                    VStack(spacing: 8) {
                        ForEach(apps) { app in
                            NetworkAppUsageRow(app: app)
                        }
                    }
                }
            }

            SectionBlock(title: "Live Links", symbol: "antenna.radiowaves.left.and.right") {
                if monitor.snapshot.network.interfaces.isEmpty {
                    EmptyState(text: "No active network interfaces reported.")
                } else {
                    VStack(spacing: 8) {
                        ForEach(monitor.snapshot.network.interfaces) { item in
                            NetworkInterfaceRow(item: item)
                        }
                    }
                }
            }

            SectionBlock(title: "Active Destinations", symbol: "location.viewfinder") {
                if monitor.snapshot.network.connections.isEmpty {
                    EmptyState(text: "No established TCP connections found.")
                } else {
                    VStack(spacing: 8) {
                        ForEach(monitor.snapshot.network.connections) { connection in
                            NetworkConnectionRow(connection: connection)
                        }
                    }
                }
            }
        }
    }

    private var health: some View {
        VStack(alignment: .leading, spacing: 16) {
            LazyVGrid(columns: detailColumns, spacing: 12) {
                DetailMetricCard(
                    icon: "gauge.with.dots.needle.67percent",
                    tint: healthTint,
                    title: "System Health",
                    value: healthValue,
                    detail: healthDetail,
                    progress: nil
                )

                DetailMetricCard(
                    icon: "cpu",
                    tint: .orange,
                    title: "CPU Pressure",
                    value: monitor.snapshot.cpu.primaryText,
                    detail: monitor.snapshot.cpu.detailText,
                    progress: monitor.snapshot.cpu.usageRatio
                )

                DetailMetricCard(
                    icon: "memorychip",
                    tint: .teal,
                    title: "Memory Pressure",
                    value: monitor.snapshot.memory.primaryText,
                    detail: monitor.snapshot.memory.detailText,
                    progress: monitor.snapshot.memory.usedRatio
                )

                DetailMetricCard(
                    icon: "internaldrive",
                    tint: .indigo,
                    title: "Storage Pressure",
                    value: monitor.snapshot.disk.primaryText,
                    detail: monitor.snapshot.disk.detailText,
                    progress: monitor.snapshot.disk.usedRatio
                )

            }

            SectionBlock(title: "Needs Attention", symbol: "exclamationmark.triangle") {
                if healthHighlights.isEmpty {
                    EmptyState(text: "Nothing needs attention right now.")
                } else {
                    VStack(spacing: 8) {
                        ForEach(healthHighlights) { item in
                            HealthHighlightRow(item: item)
                        }
                    }
                }
            }

            SectionBlock(title: "System Signals", symbol: "waveform.path.ecg.rectangle") {
                VStack(spacing: 8) {
                    ForEach(monitor.snapshot.sensors.readings.filter { $0.label != "Power Mode" && $0.label != "Adapter" }) { reading in
                        PlainInfoRow(title: reading.label, value: reading.value, detail: reading.detail)
                    }
                }
            }
        }
    }

    private var github: some View {
        GitHubSyncView(monitor: gitHubSync)
    }

    private var healthValue: String {
        if monitor.snapshot.sensors.thermalState == "Serious" || monitor.snapshot.sensors.thermalState == "Critical" {
            return "Thermal"
        }

        if monitor.snapshot.memory.usedRatio >= 0.85 {
            return "Memory"
        }

        if monitor.snapshot.disk.usedRatio >= 0.9 {
            return "Storage"
        }

        if monitor.snapshot.topPowerApp?.powerImpactText == "High" {
            return "App Load"
        }

        if monitor.snapshot.sensors.lowPowerMode {
            return "Low Power"
        }

        return "Steady"
    }

    private var healthTint: Color {
        switch healthValue {
        case "Steady":
            return .green
        case "Low Power":
            return .mint
        case "Memory", "Storage", "App Load":
            return .yellow
        case "Thermal":
            return .orange
        default:
            return .secondary
        }
    }

    private var healthDetail: String {
        "CPU \(monitor.snapshot.cpu.primaryText) • Memory \(monitor.snapshot.memory.primaryText) • Storage \(monitor.snapshot.disk.usedRatio.percentString)"
    }

    private var healthHighlights: [HealthHighlight] {
        var items: [HealthHighlight] = []

        if monitor.snapshot.sensors.thermalState != "Nominal" {
            items.append(
                HealthHighlight(
                    title: "Thermal",
                    value: monitor.snapshot.sensors.thermalState,
                    detail: monitor.snapshot.sensors.thermalDetail,
                    symbol: "thermometer.medium",
                    tint: .orange
                )
            )
        }

        if monitor.snapshot.memory.usedRatio >= 0.8 {
            items.append(
                HealthHighlight(
                    title: "Memory",
                    value: monitor.snapshot.memory.primaryText,
                    detail: monitor.snapshot.topMemoryApps.first.map { "\($0.name) is using \($0.memoryDetailText)" } ?? monitor.snapshot.memory.detailText,
                    symbol: "memorychip",
                    tint: .teal
                )
            )
        }

        if monitor.snapshot.disk.usedRatio >= 0.8 {
            items.append(
                HealthHighlight(
                    title: "Storage",
                    value: monitor.snapshot.disk.primaryText,
                    detail: monitor.snapshot.storageNudge,
                    symbol: "internaldrive",
                    tint: .indigo
                )
            )
        }

        if let app = monitor.snapshot.topPowerApp, app.powerImpactText == "High" || app.cpuRatio >= 0.20 {
            items.append(
                HealthHighlight(
                    title: "App Load",
                    value: app.name,
                    detail: app.powerDetailText,
                    symbol: "bolt.horizontal",
                    tint: .yellow
                )
            )
        }

        if let app = monitor.snapshot.networkDataApps.first, app.networkBytesPerSecond > 250_000 {
            items.append(
                HealthHighlight(
                    title: "Network",
                    value: app.name,
                    detail: "\(app.networkText) now • \(app.networkTotalText) total",
                    symbol: "arrow.up.arrow.down",
                    tint: .blue
                )
            )
        }

        if let folder = monitor.snapshot.storageAnalysis.folderHotspots.first, folder.bytes >= 2_000_000_000 {
            items.append(
                HealthHighlight(
                    title: "Storage Hotspot",
                    value: folder.name,
                    detail: "\(folder.sizeText) • \(folder.fileCount.formatted()) files",
                    symbol: "folder.badge.questionmark",
                    tint: .pink
                )
            )
        }

        return items
    }

    private var appUsageWindowHistories: [AppUsageHistory] {
        let activeKeys = Set(monitor.snapshot.topApps.map(\.historyKey))

        return monitor.appHistories.values
            .filter { activeKeys.contains($0.id) }
            .sorted {
                if $0.peakImpactScore == $1.peakImpactScore {
                    return $0.transferredBytes > $1.transferredBytes
                }

                return $0.peakImpactScore > $1.peakImpactScore
            }
    }

    private var detailColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 185), spacing: 12)]
    }
}

private enum DetailSection: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case power = "Power"
    case storage = "Storage"
    case apps = "Apps"
    case network = "Network"
    case health = "Health"
    case github = "GitHub"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .overview:
            return "opticaldiscdrive"
        case .power:
            return "bolt.horizontal"
        case .storage:
            return "internaldrive"
        case .apps:
            return "app.connected.to.app.below.fill"
        case .network:
            return "arrow.up.arrow.down"
        case .health:
            return "gauge.with.dots.needle.67percent"
        case .github:
            return "arrow.triangle.2.circlepath"
        }
    }
}

private enum DetailAppMetricKind {
    case cpu
    case memory
}

private struct HealthHighlight: Identifiable {
    var id: String { "\(title)-\(value)" }

    let title: String
    let value: String
    let detail: String
    let symbol: String
    let tint: Color
}

private struct HealthHighlightRow: View {
    let item: HealthHighlight

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: item.symbol)
                .foregroundStyle(item.tint)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                Text(item.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 12)

            Text(item.value)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(item.tint)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .rowBackground()
    }
}

private struct AppUsageWindowRow: View {
    let history: AppUsageHistory

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "clock.arrow.circlepath")
                .foregroundStyle(.indigo)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(history.name)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("\(history.sourceText) • \(history.observedText)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 12)

            HStack(spacing: 12) {
                usageMetric(title: "CPU", value: history.peakCPUText, color: cpuColor)
                usageMetric(title: "RAM", value: history.peakMemoryText, color: memoryColor)
                usageMetric(title: "DATA", value: history.transferredText, color: .blue)
            }
        }
        .rowBackground()
    }

    private func usageMetric(title: String, value: String, color: Color) -> some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(title)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(color)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(width: 54, alignment: .trailing)
    }

    private var cpuColor: Color {
        switch history.peakCPURatio {
        case 0.20...:
            return .red
        case 0.08..<0.20:
            return .orange
        default:
            return .primary
        }
    }

    private var memoryColor: Color {
        switch history.peakMemoryRatio {
        case 0.15...:
            return .red
        case 0.07..<0.15:
            return .orange
        default:
            return .primary
        }
    }
}

private struct DetailMetricCard: View {
    let icon: String
    let tint: Color
    let title: String
    let value: String
    let detail: String
    let progress: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundStyle(tint)
                    .frame(width: 20)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
            }

            Text(value)
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            if let progress {
                ProgressView(value: progress)
                    .tint(tint)
                    .controlSize(.small)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.separator.opacity(0.4), lineWidth: 1)
        )
    }
}

private struct SectionBlock<Content: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .foregroundStyle(.secondary)
                    .frame(width: 18)
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
            }

            content
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

private struct AppImpactSection: View {
    let title: String
    let symbol: String
    let apps: [AppUsageMetric]
    let histories: [String: AppUsageHistory]
    let emptyText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .foregroundStyle(.secondary)
                    .frame(width: 18)
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Text("\(apps.count)")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            if apps.isEmpty {
                EmptyState(text: emptyText)
            } else {
                VStack(spacing: 4) {
                    AppImpactHeader()
                    ForEach(apps) { app in
                        AppImpactRow(app: app, history: histories[app.historyKey])
                    }
                }
            }
        }
    }
}

private struct AppImpactHeader: View {
    var body: some View {
        HStack(spacing: 8) {
            Text("APP")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("CPU")
                .frame(width: 48, alignment: .trailing)
            Text("MEM")
                .frame(width: 70, alignment: .trailing)
            Text("NET")
                .frame(width: 68, alignment: .trailing)
            Text("DATA")
                .frame(width: 70, alignment: .trailing)
            Text("FILES")
                .frame(width: 40, alignment: .trailing)
            Text("SYS")
                .frame(width: 40, alignment: .trailing)
            Text("DISK")
                .frame(width: 60, alignment: .trailing)
            Text("IMPACT")
                .frame(width: 56, alignment: .trailing)
        }
        .font(.system(size: 10, weight: .bold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
    }
}

private struct AppImpactRow: View {
    let app: AppUsageMetric
    let history: AppUsageHistory?
    @State private var isInspecting = false

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 7) {
                Image(systemName: app.isVisible ? "macwindow" : "gearshape")
                    .foregroundStyle(app.isVisible ? .indigo : .secondary)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 1) {
                    Text(app.name)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(app.rowSubtitle)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                Button {
                    isInspecting.toggle()
                } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.borderless)
                .help("Inspect")
                .popover(isPresented: $isInspecting, arrowEdge: .trailing) {
                    ProcessInspectorView(app: app, history: history)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture {
                isInspecting.toggle()
            }

            Text(app.cpuText)
                .metricColumn(width: 48, color: app.cpuPressureColor)
                .help(app.cpuDetailText)
            Text(app.memoryText)
                .metricColumn(width: 70, color: app.memoryPressureColor)
                .help(app.memoryDetailText)
            Text(app.networkText)
                .metricColumn(width: 68, color: (app.networkConnectionCount > 0 || app.networkBytesPerSecond > 0) ? .cyan : .secondary)
                .help(app.networkDetailText)
            Text(app.networkTotalText)
                .metricColumn(width: 70, color: app.networkTotalBytes > 0 ? .blue : .secondary)
                .help(app.networkDetailText)
            Text(app.fileAccessText)
                .metricColumn(width: 40, color: app.fileAccessCount > 0 ? .indigo : .secondary)
            Text(app.systemAccessText)
                .metricColumn(width: 40, color: app.systemAccessCount > 0 ? .pink : .secondary)
            Text(app.storageText)
                .metricColumn(width: 60, color: app.storageBytes == nil ? .secondary : .pink)
            Text(app.powerImpactText)
                .metricColumn(width: 56, color: impactColor)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.separator.opacity(0.3), lineWidth: 1)
        )
        .help(app.inspectionText)
    }

    private var impactColor: Color {
        switch app.powerImpactText {
        case "High":
            return .red
        case "Medium":
            return .yellow
        case "Low":
            return .secondary
        default:
            return .secondary
        }
    }
}

private struct ProcessInspectorView: View {
    let app: AppUsageMetric
    let history: AppUsageHistory?
    private let metricColumns = [GridItem(.adaptive(minimum: 78), spacing: 8)]

    private var revealURL: URL? {
        let path = app.storagePath ?? app.commandPath
        var isDirectory: ObjCBool = false

        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else {
            return nil
        }

        return URL(fileURLWithPath: path)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: app.isVisible ? "macwindow" : "gearshape")
                    .foregroundStyle(app.isVisible ? .indigo : .secondary)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(app.name)
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(1)
                    Text(app.sourceText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            Text(app.sourceDetailText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            VStack(spacing: 7) {
                InspectorInfoRow(title: "PID", value: "\(app.pid)")
                InspectorInfoRow(title: "Parent", value: app.parentSummary ?? "-")
                InspectorInfoRow(title: "Owner", value: app.ownerName ?? "-")
                InspectorInfoRow(title: "Bundle", value: app.bundleIdentifier ?? "-")
                InspectorInfoRow(title: "Path", value: app.commandPath)
            }

            Divider()

            LazyVGrid(columns: metricColumns, spacing: 8) {
                InspectorMetricPill(title: "CPU", value: app.cpuText, tint: app.cpuPressureColor)
                InspectorMetricPill(title: "RAM", value: app.memoryText, tint: app.memoryPressureColor)
                InspectorMetricPill(title: "LIVE", value: app.networkText, tint: .cyan)
                InspectorMetricPill(title: "DATA", value: app.networkTotalText, tint: .blue)
                InspectorMetricPill(title: "FILES", value: app.fileAccessText, tint: .indigo)
                InspectorMetricPill(title: "IMPACT", value: app.powerImpactText, tint: .yellow)
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("History", systemImage: "clock")
                        .font(.system(size: 12, weight: .semibold))
                    Spacer()
                    Text(history?.observedText ?? "Collecting")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                AppUsageHistoryChart(history: history)

                LazyVGrid(columns: metricColumns, spacing: 8) {
                    InspectorMetricPill(title: "AVG CPU", value: history?.averageCPUText ?? "-", tint: .orange)
                    InspectorMetricPill(title: "PEAK CPU", value: history?.peakCPUText ?? "-", tint: .orange)
                    InspectorMetricPill(title: "PEAK RAM", value: history?.peakMemoryText ?? "-", tint: .teal)
                    InspectorMetricPill(title: "SEEN DATA", value: history?.transferredText ?? "-", tint: .blue)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Label("Why", systemImage: "questionmark.circle")
                    .font(.system(size: 12, weight: .semibold))

                VStack(spacing: 7) {
                    ForEach(app.whyReasons) { reason in
                        AppUsageReasonRow(reason: reason)
                    }
                }
            }

            if let revealURL {
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([revealURL])
                } label: {
                    Label("Reveal", systemImage: "arrow.up.right.square")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(14)
        .frame(width: 440, alignment: .leading)
    }
}

private struct AppUsageHistoryChart: View {
    let history: AppUsageHistory?

    var body: some View {
        Canvas { context, size in
            let gridColor = Color.secondary.opacity(0.16)
            let midY = size.height * 0.5

            var grid = Path()
            grid.move(to: CGPoint(x: 0, y: midY))
            grid.addLine(to: CGPoint(x: size.width, y: midY))
            context.stroke(grid, with: .color(gridColor), lineWidth: 1)

            context.stroke(
                path(for: history?.memoryValues ?? [], in: size),
                with: .color(.teal),
                style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
            )

            context.stroke(
                path(for: history?.cpuValues ?? [], in: size),
                with: .color(.orange),
                style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
            )

            context.stroke(
                path(for: history?.networkValues ?? [], in: size),
                with: .color(.blue),
                style: StrokeStyle(lineWidth: 1.7, lineCap: .round, lineJoin: .round)
            )
        }
        .frame(height: 92)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.separator.opacity(0.35), lineWidth: 1)
        )
        .overlay(alignment: .bottomLeading) {
            HStack(spacing: 10) {
                ChartLegendDot(title: "CPU", color: .orange)
                ChartLegendDot(title: "RAM", color: .teal)
                ChartLegendDot(title: "NET", color: .blue)
            }
            .padding(8)
        }
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

private struct ChartLegendDot: View {
    let title: String
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(title)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
        }
    }
}

private struct AppUsageReasonRow: View {
    let reason: AppUsageReason

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: reason.symbol)
                .foregroundStyle(reason.tint)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(reason.title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                Text(reason.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(reason.tint.opacity(0.07))
        )
    }
}

private struct InspectorInfoRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 48, alignment: .leading)

            Text(value)
                .font(.caption)
                .lineLimit(2)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
    }
}

private struct InspectorMetricPill: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(tint)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(tint.opacity(0.08))
        )
    }
}

private struct StorageCandidateRow: View {
    let item: StorageItemMetric

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "doc")
                .foregroundStyle(.indigo)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(item.detailText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 12)

            Text(item.sizeText)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)

            Button {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: item.path)])
            } label: {
                Image(systemName: "arrow.up.right.square")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.borderless)
            .help("Reveal in Finder")
        }
        .rowBackground()
    }
}

private struct StorageCategoryRow: View {
    let category: StorageCategoryMetric

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: iconName)
                .foregroundStyle(tint)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(category.title)
                    .font(.system(size: 13, weight: .medium))
                Text(category.detailText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Text(category.bytes.byteString)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .monospacedDigit()
        }
        .rowBackground()
    }

    private var iconName: String {
        switch category.kind {
        case .downloads:
            return "arrow.down.circle"
        case .documents:
            return "doc.text"
        case .media:
            return "photo.on.rectangle"
        case .caches:
            return "bolt.horizontal.circle"
        case .appSupport:
            return "app.badge"
        case .containers:
            return "shippingbox"
        case .developer, .packageBuilds:
            return "hammer"
        case .logs:
            return "doc.plaintext"
        case .other:
            return "folder"
        }
    }

    private var tint: Color {
        switch category.kind.reviewPriority {
        case 2:
            return .orange
        case 1:
            return .yellow
        default:
            return .secondary
        }
    }
}

private struct StorageFolderRow: View {
    let folder: StorageFolderMetric

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: folder.kind.reviewPriority > 0 ? "folder.badge.minus" : "folder")
                .foregroundStyle(folder.kind.reviewPriority > 0 ? .orange : .indigo)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(folder.name)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(folder.detailText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 12)

            Text(folder.sizeText)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .monospacedDigit()

            Button {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: folder.path)])
            } label: {
                Image(systemName: "arrow.up.right.square")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.borderless)
            .help("Reveal in Finder")
        }
        .rowBackground()
    }
}

private struct AppUsageRow: View {
    let app: AppUsageMetric
    let totalMemory: UInt64

    private var memoryRatio: Double {
        guard totalMemory > 0 else { return 0 }
        return min(max(Double(app.residentBytes) / Double(totalMemory), 0), 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 10) {
                Image(systemName: "app")
                    .foregroundStyle(.teal)
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 2) {
                    Text(app.name)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                    Text(app.detailText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(app.memoryText)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(app.memoryPressureColor)
                    .monospacedDigit()
                    .help(app.memoryDetailText)
            }

            ProgressView(value: memoryRatio)
                .tint(app.memoryPressureColor)
                .controlSize(.small)
        }
        .rowBackground()
        .help(app.inspectionText)
    }
}

private struct DetailAppMetricRow: View {
    let app: AppUsageMetric
    let metric: DetailAppMetricKind
    let tint: Color

    private var valueText: String {
        switch metric {
        case .cpu:
            return app.cpuText
        case .memory:
            return app.memoryText
        }
    }

    private var secondaryText: String {
        switch metric {
        case .cpu:
            return app.memoryText
        case .memory:
            return app.cpuText
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: metric == .cpu ? "cpu" : "memorychip")
                .foregroundStyle(tint)
                .frame(width: 22)

            Text(app.name)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 12)

            Text(secondaryText)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .lineLimit(1)

            Text(valueText)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(metricColor)
                .monospacedDigit()
                .lineLimit(1)
        }
        .rowBackground()
        .help(app.inspectionText)
    }

    private var metricColor: Color {
        switch metric {
        case .cpu:
            return app.cpuPressureColor
        case .memory:
            return app.memoryPressureColor
        }
    }
}

private struct PowerUsageRow: View {
    let app: AppUsageMetric

    private var impactRatio: Double {
        min(max(app.powerImpactScore / 55.0, 0), 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 10) {
                Image(systemName: "bolt.horizontal")
                    .foregroundStyle(.yellow)
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 2) {
                    Text(app.name)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                    Text(app.powerDetailText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Text(app.powerImpactText)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .lineLimit(1)
            }

            ProgressView(value: impactRatio)
                .tint(.yellow)
                .controlSize(.small)
        }
        .rowBackground()
        .help(app.inspectionText)
    }
}

private struct NetworkAppUsageRow: View {
    let app: AppUsageMetric

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: app.isVisible ? "macwindow" : "gearshape")
                .foregroundStyle(app.isVisible ? .indigo : .secondary)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(app.name)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("\(app.sourceText) • \(app.networkDetailText)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 2) {
                Text(app.networkTotalText)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(app.networkTotalBytes > 0 ? .blue : .secondary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text(app.networkText)
                    .font(.caption)
                    .foregroundStyle((app.networkBytesPerSecond > 0 || app.networkConnectionCount > 0) ? .cyan : .secondary)
                    .monospacedDigit()
                    .lineLimit(1)
            }
        }
        .rowBackground()
        .help(app.inspectionText)
    }
}

private struct NetworkInterfaceRow: View {
    let item: NetworkInterfaceMetric

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "network")
                .foregroundStyle(.cyan)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayName)
                    .font(.system(size: 13, weight: .medium))
                Text(item.detailText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(item.totalText)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.blue)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text(item.primaryText)
                    .font(.caption)
                    .foregroundStyle(.cyan)
                    .monospacedDigit()
                    .lineLimit(1)
            }
        }
        .rowBackground()
        .help(item.inspectionText)
    }
}

private struct NetworkConnectionRow: View {
    let connection: NetworkConnectionMetric

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label(connection.sourceText, systemImage: "point.3.connected.trianglepath.dotted")
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)

                Spacer()

                Text(connection.statusText)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }

            Text(connection.detailText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Text(connection.routeText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospaced()
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .rowBackground()
        .help(connection.inspectionText)
    }
}

private struct PlainInfoRow: View {
    let title: String
    let value: String
    let detail: String

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .rowBackground()
    }
}

private struct EmptyState: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .rowBackground()
    }
}

private extension View {
    func metricColumn(width: CGFloat, color: Color) -> some View {
        font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(color)
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(width: width, alignment: .trailing)
    }

    func rowBackground() -> some View {
        padding(10)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(.separator.opacity(0.35), lineWidth: 1)
            )
    }
}
