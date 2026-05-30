import Darwin
import Foundation
import IOKit
import IOKit.ps
import Metal
import SwiftUI

struct SystemSnapshot {
    let disk: DiskMetric
    let cpu: CPUMetric
    let memory: MemoryMetric
    let battery: BatteryMetric
    let network: NetworkMetric
    let gpu: GPUMetric
    let topApps: [AppUsageMetric]
    let storageCandidates: [StorageItemMetric]
    let storageAnalysis: StorageAnalysisMetric
    let sensors: SensorStatusMetric
    let cpuHistory: [Double]
    let memoryHistory: [Double]
    let updatedAt: Date

    var menuBarTitle: String {
        "Disko"
    }

    var updatedText: String {
        "Updated \(updatedAt.formatted(date: .omitted, time: .standard))"
    }

    var storageNudge: String {
        if disk.usedRatio >= 0.9 {
            return "Storage is tight. Start with old exports and large downloads."
        }

        if disk.usedRatio >= 0.75 {
            return "Storage is getting dense. Disko found cleanup candidates below."
        }

        return "Plenty of creative room on this Mac."
    }

    var topPowerApps: [AppUsageMetric] {
        topApps.sorted {
            if $0.powerImpactScore == $1.powerImpactScore {
                return $0.residentBytes > $1.residentBytes
            }

            return $0.powerImpactScore > $1.powerImpactScore
        }
    }

    var topPowerApp: AppUsageMetric? {
        topPowerApps.first
    }

    var topCPUApps: [AppUsageMetric] {
        topApps
            .filter { $0.cpuPercent >= 0.3 }
            .sorted {
                if $0.cpuPercent == $1.cpuPercent {
                    return $0.residentBytes > $1.residentBytes
                }

                return $0.cpuPercent > $1.cpuPercent
            }
    }

    var topMemoryApps: [AppUsageMetric] {
        topApps
            .filter { $0.residentBytes >= 20_000_000 }
            .sorted {
                if $0.residentBytes == $1.residentBytes {
                    return $0.cpuPercent > $1.cpuPercent
                }

                return $0.residentBytes > $1.residentBytes
            }
    }

    var visibleApps: [AppUsageMetric] {
        let apps = topApps
            .filter(\.isVisible)
            .sorted(by: AppUsageMetric.impactSort)

        if apps.isEmpty {
            return topApps
                .sorted(by: AppUsageMetric.impactSort)
                .prefix(30)
                .map { $0 }
        }

        return apps
    }

    var backgroundApps: [AppUsageMetric] {
        topApps
            .filter { !$0.isVisible }
            .sorted(by: AppUsageMetric.impactSort)
    }

    var networkActiveApps: [AppUsageMetric] {
        topApps
            .filter { $0.networkConnectionCount > 0 || $0.networkBytesPerSecond > 0 || $0.networkTotalBytes > 0 }
            .sorted {
                if $0.networkBytesPerSecond == $1.networkBytesPerSecond {
                    if $0.networkTotalBytes != $1.networkTotalBytes {
                        return $0.networkTotalBytes > $1.networkTotalBytes
                    }

                    if $0.networkConnectionCount == $1.networkConnectionCount {
                        return AppUsageMetric.impactSort($0, $1)
                    }

                    return $0.networkConnectionCount > $1.networkConnectionCount
                }

                return $0.networkBytesPerSecond > $1.networkBytesPerSecond
            }
    }

    var networkDataApps: [AppUsageMetric] {
        topApps
            .filter { $0.networkTotalBytes > 0 || $0.networkBytesPerSecond > 0 || $0.networkConnectionCount > 0 }
            .sorted {
                if $0.networkTotalBytes == $1.networkTotalBytes {
                    if $0.networkBytesPerSecond == $1.networkBytesPerSecond {
                        return AppUsageMetric.impactSort($0, $1)
                    }

                    return $0.networkBytesPerSecond > $1.networkBytesPerSecond
                }

                return $0.networkTotalBytes > $1.networkTotalBytes
            }
    }

    var systemAccessApps: [AppUsageMetric] {
        topApps
            .filter { $0.fileAccessCount > 0 || $0.systemAccessCount > 0 }
            .sorted {
                let lhsAccess = $0.fileAccessCount + $0.systemAccessCount
                let rhsAccess = $1.fileAccessCount + $1.systemAccessCount

                if lhsAccess == rhsAccess {
                    return AppUsageMetric.impactSort($0, $1)
                }

                return lhsAccess > rhsAccess
            }
    }

    static let placeholder = SystemSnapshot(
        disk: DiskMetric(totalBytes: 1, freeBytes: 1),
        cpu: CPUMetric(usageRatio: nil, coreCount: ProcessInfo.processInfo.processorCount, activeCoreCount: ProcessInfo.processInfo.activeProcessorCount),
        memory: MemoryMetric(
            totalBytes: ProcessInfo.processInfo.physicalMemory,
            appBytes: 0,
            wiredBytes: 0,
            compressedBytes: 0,
            cachedBytes: 0,
            freeBytes: ProcessInfo.processInfo.physicalMemory
        ),
        battery: BatteryMetric(
            levelRatio: nil,
            isCharging: false,
            isPluggedIn: false,
            timeToEmptyMinutes: nil,
            timeToFullMinutes: nil,
            health: nil,
            cycleCount: nil,
            temperatureCelsius: nil,
            powerWatts: nil,
            adapterWatts: nil
        ),
        network: NetworkMetric(downloadBytesPerSecond: 0, uploadBytesPerSecond: 0, interfaces: [], connections: []),
        gpu: GPUMetric(devices: []),
        topApps: [],
        storageCandidates: [],
        storageAnalysis: .empty,
        sensors: SensorStatusMetric.placeholder,
        cpuHistory: [],
        memoryHistory: [],
        updatedAt: Date()
    )
}

struct DiskMetric {
    let totalBytes: UInt64
    let freeBytes: UInt64

    var usedBytes: UInt64 {
        totalBytes > freeBytes ? totalBytes - freeBytes : 0
    }

    var usedRatio: Double {
        guard totalBytes > 0 else { return 0 }
        return min(max(Double(usedBytes) / Double(totalBytes), 0), 1)
    }

    var primaryText: String {
        "\(freeBytes.byteString) free"
    }

    var detailText: String {
        "\(usedBytes.byteString) used of \(totalBytes.byteString)"
    }
}

struct CPUMetric {
    let usageRatio: Double?
    let coreCount: Int
    let activeCoreCount: Int

    var menuBarText: String {
        guard let usageRatio else { return "--" }
        return usageRatio.percentString
    }

    var primaryText: String {
        guard let usageRatio else { return "Warming up" }
        return usageRatio.percentString
    }

    var detailText: String {
        "\(activeCoreCount) active / \(coreCount) logical cores"
    }
}

struct MemoryMetric {
    let totalBytes: UInt64
    let appBytes: UInt64
    let wiredBytes: UInt64
    let compressedBytes: UInt64
    let cachedBytes: UInt64
    let freeBytes: UInt64

    var usedBytes: UInt64 {
        min(appBytes + wiredBytes + compressedBytes, totalBytes)
    }

    var usedRatio: Double {
        guard totalBytes > 0 else { return 0 }
        return min(max(Double(usedBytes) / Double(totalBytes), 0), 1)
    }

    var primaryText: String {
        usedRatio.percentString
    }

    var detailText: String {
        "\(usedBytes.byteString) used of \(totalBytes.byteString)"
    }

    var appText: String {
        appBytes.byteString
    }

    var wiredText: String {
        wiredBytes.byteString
    }

    var compressedText: String {
        compressedBytes.byteString
    }

    var cachedText: String {
        cachedBytes.byteString
    }
}

struct BatteryMetric {
    let levelRatio: Double?
    let isCharging: Bool
    let isPluggedIn: Bool
    let timeToEmptyMinutes: Int?
    let timeToFullMinutes: Int?
    let health: String?
    let cycleCount: Int?
    let temperatureCelsius: Double?
    let powerWatts: Double?
    let adapterWatts: Int?

    var chargeRatio: Double? {
        levelRatio
    }

    var iconName: String {
        guard let levelRatio else { return "bolt.slash" }

        if isCharging || isPluggedIn {
            return "battery.100.bolt"
        }

        switch levelRatio {
        case 0.75...:
            return "battery.100"
        case 0.35..<0.75:
            return "battery.50"
        default:
            return "battery.25"
        }
    }

    var tint: Color {
        guard let levelRatio else { return .secondary }
        if isCharging || isPluggedIn { return .green }
        return levelRatio < 0.2 ? .red : .mint
    }

    var primaryText: String {
        guard let levelRatio else { return "No battery" }
        return levelRatio.percentString
    }

    var stateText: String {
        guard levelRatio != nil else { return "Desktop power" }
        if isCharging { return "Charging" }
        if isPluggedIn { return "Plugged in" }
        return "On battery"
    }

    var detailText: String {
        guard levelRatio != nil else { return "Desktop power" }
        if isCharging, let timeToFullMinutes {
            return "Charging, full in \(timeToFullMinutes.minutesText)"
        }
        if isCharging { return "Charging" }
        if isPluggedIn { return "Plugged in" }
        if let timeToEmptyMinutes { return "\(timeToEmptyMinutes.minutesText) remaining" }
        return "On battery"
    }

    var powerDrawText: String {
        if let powerWatts, powerWatts > 0.05 {
            let direction = isPluggedIn ? "battery flow" : "draw"
            return "\(powerWatts.wattsString) \(direction)"
        }

        if let adapterWatts {
            return "\(adapterWatts) W adapter"
        }

        return "Power draw unavailable"
    }

    var adapterText: String {
        adapterWatts.map { "\($0) W adapter" } ?? "Adapter unavailable"
    }

    var healthText: String {
        var pieces: [String] = []

        if let health {
            pieces.append(health)
        }

        if let cycleCount {
            pieces.append("\(cycleCount) cycles")
        }

        if let temperatureCelsius {
            pieces.append("\(temperatureCelsius.temperatureString)")
        }

        return pieces.isEmpty ? "Health unavailable" : pieces.joined(separator: " • ")
    }
}

struct NetworkMetric {
    let downloadBytesPerSecond: UInt64
    let uploadBytesPerSecond: UInt64
    let interfaces: [NetworkInterfaceMetric]
    let connections: [NetworkConnectionMetric]

    var primaryText: String {
        "↓ \(downloadBytesPerSecond.rateString)  ↑ \(uploadBytesPerSecond.rateString)"
    }

    var detailText: String {
        if isTransmitting {
            return "Live traffic across \(interfaces.count) active links"
        }

        return "No meaningful traffic right now"
    }

    var totalReceivedBytes: UInt64 {
        interfaces.reduce(0) { $0 + $1.totalReceivedBytes }
    }

    var totalSentBytes: UInt64 {
        interfaces.reduce(0) { $0 + $1.totalSentBytes }
    }

    var totalTransferredBytes: UInt64 {
        totalReceivedBytes + totalSentBytes
    }

    var totalText: String {
        totalTransferredBytes == 0 ? "-" : totalTransferredBytes.byteString
    }

    var totalDetailText: String {
        "Down \(totalReceivedBytes.byteString) • Up \(totalSentBytes.byteString)"
    }

    var isTransmitting: Bool {
        downloadBytesPerSecond + uploadBytesPerSecond > 1_024
    }
}

struct NetworkInterfaceMetric: Identifiable {
    let id: String
    let name: String
    let displayName: String
    let downloadBytesPerSecond: UInt64
    let uploadBytesPerSecond: UInt64
    let totalReceivedBytes: UInt64
    let totalSentBytes: UInt64
    let linkSpeedBitsPerSecond: UInt64?

    var primaryText: String {
        "↓ \(downloadBytesPerSecond.rateString)  ↑ \(uploadBytesPerSecond.rateString)"
    }

    var totalBytes: UInt64 {
        totalReceivedBytes + totalSentBytes
    }

    var totalText: String {
        totalBytes == 0 ? "-" : totalBytes.byteString
    }

    var detailText: String {
        let live = "Live ↓ \(downloadBytesPerSecond.rateString) ↑ \(uploadBytesPerSecond.rateString)"

        if let linkSpeedBitsPerSecond, linkSpeedBitsPerSecond > 0 {
            return "\(live) • Link \(linkSpeedBitsPerSecond.bitRateString)"
        }

        return live
    }

    var inspectionText: String {
        "\(displayName)\nTotal \(totalText) - down \(totalReceivedBytes.byteString), up \(totalSentBytes.byteString)\n\(detailText)"
    }
}

struct NetworkConnectionMetric: Identifiable {
    let id: String
    let processName: String
    let pid: Int
    let localAddress: String
    let remoteAddress: String

    var title: String {
        "\(processName) (\(pid))"
    }

    var routeText: String {
        "\(localAddress) → \(remoteAddress)"
    }

    var sourceText: String {
        if let known = knownProcessInfo {
            return known.title
        }

        if normalizedProcessName.hasPrefix("com.apple.WebKit") || normalizedProcessName.hasPrefix("com.apple.Safar") {
            return "Safari / WebKit"
        }

        if normalizedProcessName.hasPrefix("com.apple.") {
            return "Apple service"
        }

        if normalizedProcessName.localizedCaseInsensitiveContains("helper") {
            return "\(processName) helper"
        }

        return "\(processName) traffic"
    }

    var detailText: String {
        var pieces: [String] = []

        if let known = knownProcessInfo {
            pieces.append(known.detail)
        } else if normalizedProcessName.hasPrefix("com.apple.") {
            pieces.append("Apple background networking for a system service or framework.")
        } else {
            pieces.append("Network session opened by \(processName).")
        }

        pieces.append(destinationSummary)
        return pieces.joined(separator: " ")
    }

    var destinationSummary: String {
        if let remotePort, let service = Self.portDescriptions[remotePort] {
            return "Destination uses \(service) on port \(remotePort)."
        }

        if let remotePort {
            return "Destination port \(remotePort)."
        }

        return "Destination details are limited by macOS socket reporting."
    }

    var statusText: String {
        remotePort.flatMap { Self.shortPortNames[$0] } ?? "TCP"
    }

    var inspectionText: String {
        "\(sourceText)\n\(detailText)\nPID \(pid)\n\(routeText)"
    }

    private var normalizedProcessName: String {
        processName.replacingOccurrences(of: "\\", with: "")
    }

    private var remotePort: String? {
        port(from: remoteAddress)
    }

    private func port(from endpoint: String) -> String? {
        let cleaned = endpoint
            .replacingOccurrences(of: "]", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let separator = cleaned.lastIndex(of: ":") else {
            return nil
        }

        let value = String(cleaned[cleaned.index(after: separator)...])
        return value.allSatisfy(\.isNumber) ? value : nil
    }

    private var knownProcessInfo: (title: String, detail: String)? {
        if let exact = Self.knownProcesses[normalizedProcessName] {
            return exact
        }

        return Self.knownProcessPrefixes.first { normalizedProcessName.hasPrefix($0.key) }?.value
    }

    private static let knownProcesses: [String: (title: String, detail: String)] = [
        "mDNSResponder": (
            "DNS / Bonjour",
            "macOS name lookup and local network discovery. Apps use it when resolving domains or finding nearby devices."
        ),
        "apsd": (
            "Apple Push",
            "Apple Push Notification service. It keeps a connection open for notifications and device/account updates."
        ),
        "cloudd": (
            "iCloud",
            "Apple iCloud and CloudKit traffic for sync, app data, and account-backed services."
        ),
        "bird": (
            "iCloud Drive",
            "iCloud Drive file sync traffic."
        ),
        "nsurlsessiond": (
            "Background Transfers",
            "macOS background upload/download service used by apps and system services."
        ),
        "rapportd": (
            "Continuity",
            "Apple Continuity traffic for nearby devices, Handoff, and ecosystem features."
        ),
        "sharingd": (
            "Sharing",
            "Apple sharing traffic for AirDrop, local discovery, and nearby-device features."
        ),
        "trustd": (
            "Certificate Checks",
            "Certificate trust and revocation checks used when apps verify secure connections."
        ),
        "Mail": (
            "Mail",
            "Apple Mail account traffic."
        ),
        "Spotify": (
            "Spotify",
            "Spotify streaming, metadata, or account traffic."
        ),
        "ChatGPT": (
            "ChatGPT",
            "ChatGPT app traffic."
        ),
        "Claude": (
            "Claude",
            "Claude desktop app traffic."
        ),
        "codex": (
            "Codex",
            "Codex app or CLI traffic."
        )
    ]

    private static let knownProcessPrefixes: [String: (title: String, detail: String)] = [
        "com.apple.WebKi": (
            "WebKit",
            "Apple WebKit networking. Safari and apps with embedded web views often send traffic through this process."
        ),
        "com.apple.Safar": (
            "Safari",
            "Safari or Safari support service traffic."
        ),
        "Spotify Helper": (
            "Spotify Helper",
            "Spotify helper process for playback, renderer, or background networking."
        ),
        "Claude Helper": (
            "Claude Helper",
            "Claude helper process for renderer, network, or desktop app support traffic."
        ),
        "Codex Helper": (
            "Codex Helper",
            "Codex helper process for renderer or app support traffic."
        )
    ]

    private static let portDescriptions: [String: String] = [
        "22": "SSH / secure shell",
        "53": "DNS name lookup",
        "80": "HTTP web traffic",
        "123": "network time",
        "443": "HTTPS / encrypted web traffic",
        "465": "secure mail sending",
        "587": "mail sending",
        "993": "IMAP mail sync",
        "995": "POP mail sync",
        "5223": "Apple Push Notifications",
        "5353": "Bonjour / local discovery",
        "3478": "STUN / realtime calling",
        "5349": "secure STUN/TURN realtime calling"
    ]

    private static let shortPortNames: [String: String] = [
        "22": "SSH",
        "53": "DNS",
        "80": "HTTP",
        "123": "TIME",
        "443": "HTTPS",
        "465": "MAIL",
        "587": "MAIL",
        "993": "MAIL",
        "995": "MAIL",
        "5223": "PUSH",
        "5353": "LOCAL",
        "3478": "CALL",
        "5349": "CALL"
    ]
}

struct GPUMetric {
    let devices: [GPUDeviceMetric]

    var primaryText: String {
        guard let firstName = devices.first?.name else { return "Unavailable" }
        return firstName
    }

    var detailText: String {
        if devices.isEmpty {
            return "Metal device not found"
        }

        if devices.count == 1 {
            return devices[0].detailText
        }

        return "\(devices.count) Metal devices"
    }
}

struct GPUDeviceMetric: Identifiable {
    let id: String
    let name: String
    let isLowPower: Bool
    let isRemovable: Bool
    let hasUnifiedMemory: Bool
    let recommendedMaxWorkingSetBytes: UInt64
    let currentAllocatedBytes: UInt64

    var detailText: String {
        var pieces: [String] = []
        pieces.append(hasUnifiedMemory ? "Unified memory" : "Dedicated memory")

        if recommendedMaxWorkingSetBytes > 0 {
            pieces.append("\(recommendedMaxWorkingSetBytes.byteString) working set")
        }

        if currentAllocatedBytes > 0 {
            pieces.append("\(currentAllocatedBytes.byteString) allocated")
        }

        if isLowPower {
            pieces.append("low power")
        }

        if isRemovable {
            pieces.append("external")
        }

        return pieces.joined(separator: " • ")
    }
}

struct AppUsageMetric: Identifiable {
    let id: Int
    let pid: Int
    let parentPID: Int?
    let name: String
    let commandPath: String
    let ownerName: String?
    let parentName: String?
    let bundleIdentifier: String?
    let residentBytes: UInt64
    let cpuPercent: Double
    let isVisible: Bool
    let processCount: Int
    let networkConnectionCount: Int
    let networkDownloadBytesPerSecond: UInt64
    let networkUploadBytesPerSecond: UInt64
    let networkTotalDownloadBytes: UInt64
    let networkTotalUploadBytes: UInt64
    let fileAccessCount: Int
    let systemAccessCount: Int
    let storageBytes: UInt64?
    let storagePath: String?

    init(
        id: Int,
        pid: Int,
        parentPID: Int? = nil,
        name: String,
        commandPath: String,
        ownerName: String? = nil,
        parentName: String? = nil,
        bundleIdentifier: String? = nil,
        residentBytes: UInt64,
        cpuPercent: Double,
        isVisible: Bool = false,
        processCount: Int = 1,
        networkConnectionCount: Int = 0,
        networkDownloadBytesPerSecond: UInt64 = 0,
        networkUploadBytesPerSecond: UInt64 = 0,
        networkTotalDownloadBytes: UInt64 = 0,
        networkTotalUploadBytes: UInt64 = 0,
        fileAccessCount: Int = 0,
        systemAccessCount: Int = 0,
        storageBytes: UInt64? = nil,
        storagePath: String? = nil
    ) {
        self.id = id
        self.pid = pid
        self.parentPID = parentPID
        self.name = name
        self.commandPath = commandPath
        self.ownerName = ownerName
        self.parentName = parentName
        self.bundleIdentifier = bundleIdentifier
        self.residentBytes = residentBytes
        self.cpuPercent = cpuPercent
        self.isVisible = isVisible
        self.processCount = processCount
        self.networkConnectionCount = networkConnectionCount
        self.networkDownloadBytesPerSecond = networkDownloadBytesPerSecond
        self.networkUploadBytesPerSecond = networkUploadBytesPerSecond
        self.networkTotalDownloadBytes = networkTotalDownloadBytes
        self.networkTotalUploadBytes = networkTotalUploadBytes
        self.fileAccessCount = fileAccessCount
        self.systemAccessCount = systemAccessCount
        self.storageBytes = storageBytes
        self.storagePath = storagePath
    }

    var memoryBytesText: String {
        residentBytes.byteString
    }

    var memoryRatio: Double {
        guard ProcessInfo.processInfo.physicalMemory > 0 else {
            return 0
        }

        return min(max(Double(residentBytes) / Double(ProcessInfo.processInfo.physicalMemory), 0), 1)
    }

    var memoryText: String {
        memoryRatio.percentString
    }

    var memoryDetailText: String {
        "\(memoryText) of RAM • \(memoryBytesText)"
    }

    var cpuText: String {
        cpuRatio.percentString
    }

    var rawCPUText: String {
        "\(Int(cpuPercent.rounded()))% of one core"
    }

    var cpuRatio: Double {
        let coreCapacity = max(ProcessInfo.processInfo.activeProcessorCount, 1)
        return min(max(cpuPercent / (Double(coreCapacity) * 100.0), 0), 1)
    }

    var cpuDetailText: String {
        "\(cpuText) of Mac • \(rawCPUText)"
    }

    var cpuPressureColor: Color {
        switch cpuRatio {
        case 0.20...:
            return .red
        case 0.08..<0.20:
            return .orange
        default:
            return .primary
        }
    }

    var memoryPressureColor: Color {
        switch memoryRatio {
        case 0.15...:
            return .red
        case 0.07..<0.15:
            return .orange
        default:
            return .primary
        }
    }

    var historyKey: String {
        if let bundleIdentifier {
            return "bundle:\(bundleIdentifier)"
        }

        if let storagePath {
            return "path:\(storagePath)"
        }

        if !commandPath.isEmpty {
            return "command:\(commandPath)"
        }

        return "pid:\(pid)"
    }

    var networkText: String {
        if networkBytesPerSecond > 0 {
            return networkBytesPerSecond.rateString
        }

        return networkConnectionCount == 0 ? "-" : "\(networkConnectionCount)"
    }

    var networkBytesPerSecond: UInt64 {
        networkDownloadBytesPerSecond + networkUploadBytesPerSecond
    }

    var networkTotalBytes: UInt64 {
        networkTotalDownloadBytes + networkTotalUploadBytes
    }

    var networkTotalText: String {
        networkTotalBytes == 0 ? "-" : networkTotalBytes.byteString
    }

    var networkDetailText: String {
        var pieces: [String] = []

        if networkBytesPerSecond > 0 {
            pieces.append("Live down \(networkDownloadBytesPerSecond.rateString), up \(networkUploadBytesPerSecond.rateString)")
        } else {
            pieces.append("Live idle")
        }

        if networkTotalBytes > 0 {
            pieces.append("Total down \(networkTotalDownloadBytes.byteString), up \(networkTotalUploadBytes.byteString)")
        } else {
            pieces.append("Total unavailable")
        }

        if networkConnectionCount > 0 {
            pieces.append("\(networkConnectionCount) links")
        }

        return pieces.joined(separator: " | ")
    }

    var fileAccessText: String {
        fileAccessCount == 0 ? "-" : "\(fileAccessCount)"
    }

    var systemAccessText: String {
        systemAccessCount == 0 ? "-" : "\(systemAccessCount)"
    }

    var storageText: String {
        storageBytes?.byteString ?? "-"
    }

    var powerImpactScore: Double {
        let memoryGB = Double(residentBytes) / 1_000_000_000
        let networkMB = Double(networkBytesPerSecond) / 1_000_000
        let networkScore = (Double(networkConnectionCount) * 1.2) + (networkMB * 6.0)
        let storageGB = Double(storageBytes ?? 0) / 1_000_000_000
        let accessScore = min(Double(fileAccessCount) / 50.0, 5.0) + min(Double(systemAccessCount) / 40.0, 5.0)
        return (cpuPercent * 2.0) + (memoryGB * 8.0) + networkScore + accessScore + (storageGB * 0.08)
    }

    var powerImpactText: String {
        switch powerImpactScore {
        case 35...:
            return "High"
        case 14..<35:
            return "Medium"
        case 4..<14:
            return "Low"
        default:
            return "Idle"
        }
    }

    var powerDetailText: String {
        "CPU \(cpuText) • RAM \(memoryDetailText) • Live \(networkText) • Data \(networkTotalText)"
    }

    var detailText: String {
        "\(rowSubtitle) • \(cpuDetailText)"
    }

    var rowSubtitle: String {
        if isVisible {
            return processCount > 1 ? "\(processCount) processes" : "PID \(pid)"
        }

        return "\(sourceText) • PID \(pid)"
    }

    var sourceText: String {
        if isVisible {
            return "Visible app"
        }

        if let known = knownServiceInfo {
            return known.title
        }

        if let appName = appBundleName {
            return helperSourceTitle(appName: appName)
        }

        if let xpcServiceName {
            return "\(xpcServiceName) XPC"
        }

        if let frameworkName {
            return "\(frameworkName) service"
        }

        if let supportOwner = applicationSupportOwner {
            return "\(supportOwner) support"
        }

        if isAppleSystemPath {
            return "macOS service"
        }

        if commandPath.hasPrefix(NSHomeDirectory() + "/") {
            return "User agent"
        }

        if commandPath.hasPrefix("/Library/") {
            return "System-wide component"
        }

        return "Background process"
    }

    var sourceDetailText: String {
        if isVisible {
            if processCount > 1 {
                return "Combined view of \(processCount) processes that belong to this app, including helpers, renderers, networking, and GPU workers when Disko can map them back to the app bundle."
            }

            return "Main visible app process. If helper processes exist, Disko rolls them into this row when they can be mapped to the same app bundle."
        }

        if let known = knownServiceInfo {
            return known.detail
        }

        if let appName = appBundleName {
            return helperDetail(appName: appName)
        }

        if let xpcServiceName {
            let parent = parentName.map { " It was launched by \($0)." } ?? ""
            return "\(xpcServiceName) is a sandboxed XPC service. These usually do a specific task for an app or macOS framework.\(parent)"
        }

        if let frameworkName {
            let parent = parentName.map { " Parent: \($0)." } ?? ""
            return "Apple framework support process from \(frameworkName). It usually appears when macOS or an app is using that framework.\(parent)"
        }

        if let supportOwner = applicationSupportOwner {
            return "Runs from Application Support for \(supportOwner). This usually means a user-installed app, updater, plug-in, or helper stored its runtime files there."
        }

        if isAppleSystemPath {
            let parent = parentName.map { " Parent: \($0)." } ?? ""
            return "Apple system process launched by macOS from \(systemPathArea).\(parent)"
        }

        if commandPath.hasPrefix(NSHomeDirectory() + "/") {
            let parent = parentName.map { " Parent: \($0)." } ?? ""
            return "User-level process from your home folder. It may belong to a developer tool, updater, script, or app support folder.\(parent)"
        }

        if commandPath.hasPrefix("/Library/") {
            let parent = parentName.map { " Parent: \($0)." } ?? ""
            return "System-wide installed component. This is often from a login item, driver, helper, or third-party background service.\(parent)"
        }

        let parent = parentName.map { " Parent: \($0)." } ?? ""
        return "Disko could not map this to an app bundle. Check the path, parent, and owner for the best clue.\(parent)"
    }

    var inspectionText: String {
        var lines = [
            "\(name) - \(sourceText)",
            sourceDetailText,
            "PID \(pid)\(parentSummary.map { " • Parent \($0)" } ?? "")",
            "Owner \(ownerName ?? "unknown")",
            "Path \(commandPath)"
        ]

        if let bundleIdentifier {
            lines.append("Bundle \(bundleIdentifier)")
        }

        lines.append("\(cpuDetailText) • RAM \(memoryDetailText) • \(networkDetailText) • Files \(fileAccessText) • Sys \(systemAccessText)")
        return lines.joined(separator: "\n")
    }

    func preservingSampledDetails(
        from previous: AppUsageMetric?,
        includeNetwork: Bool,
        includeAccess: Bool
    ) -> AppUsageMetric {
        guard let previous else {
            return self
        }

        return AppUsageMetric(
            id: id,
            pid: pid,
            parentPID: parentPID,
            name: name,
            commandPath: commandPath,
            ownerName: ownerName,
            parentName: parentName,
            bundleIdentifier: bundleIdentifier,
            residentBytes: residentBytes,
            cpuPercent: cpuPercent,
            isVisible: isVisible,
            processCount: processCount,
            networkConnectionCount: includeNetwork ? networkConnectionCount : previous.networkConnectionCount,
            networkDownloadBytesPerSecond: includeNetwork ? networkDownloadBytesPerSecond : previous.networkDownloadBytesPerSecond,
            networkUploadBytesPerSecond: includeNetwork ? networkUploadBytesPerSecond : previous.networkUploadBytesPerSecond,
            networkTotalDownloadBytes: includeNetwork ? networkTotalDownloadBytes : previous.networkTotalDownloadBytes,
            networkTotalUploadBytes: includeNetwork ? networkTotalUploadBytes : previous.networkTotalUploadBytes,
            fileAccessCount: includeAccess ? fileAccessCount : previous.fileAccessCount,
            systemAccessCount: includeAccess ? systemAccessCount : previous.systemAccessCount,
            storageBytes: storageBytes ?? previous.storageBytes,
            storagePath: storagePath ?? previous.storagePath
        )
    }

    var whyReasons: [AppUsageReason] {
        var reasons: [AppUsageReason] = []

        if let serviceReason {
            reasons.append(serviceReason)
        } else {
            reasons.append(
                AppUsageReason(
                    title: sourceText,
                    detail: sourceDetailText,
                    symbol: isVisible ? "macwindow" : "gearshape",
                    tint: isVisible ? .indigo : .secondary
                )
            )
        }

        if cpuRatio >= 0.08 {
            reasons.append(
                AppUsageReason(
                    title: cpuRatio >= 0.20 ? "High CPU" : "CPU Activity",
                    detail: "\(cpuDetailText). macOS reports raw process CPU per core, so Disko normalizes this to the whole Mac.",
                    symbol: "cpu",
                    tint: cpuPressureColor
                )
            )
        }

        if memoryRatio >= 0.07 {
            reasons.append(
                AppUsageReason(
                    title: memoryRatio >= 0.15 ? "High Memory" : "Memory Use",
                    detail: "\(memoryDetailText). Large app bundles, renderers, media sessions, and developer tools can keep memory resident.",
                    symbol: "memorychip",
                    tint: memoryPressureColor
                )
            )
        }

        if networkBytesPerSecond > 0 || networkTotalBytes > 250_000_000 {
            reasons.append(
                AppUsageReason(
                    title: "Network Transfer",
                    detail: networkDetailText,
                    symbol: "arrow.up.arrow.down",
                    tint: .blue
                )
            )
        }

        if fileAccessCount >= 50 {
            reasons.append(
                AppUsageReason(
                    title: "File Activity",
                    detail: "\(fileAccessCount.formatted()) open user-file handles. This often points to sync, indexing, scanning, rendering, or project files being read.",
                    symbol: "doc.text.magnifyingglass",
                    tint: .indigo
                )
            )
        }

        if systemAccessCount >= 50 {
            reasons.append(
                AppUsageReason(
                    title: "System Access",
                    detail: "\(systemAccessCount.formatted()) system/framework/device handles. This is common for system services, app helpers, audio, display, and networking work.",
                    symbol: "externaldrive.connected.to.line.below",
                    tint: .pink
                )
            )
        }

        return Array(reasons.prefix(5))
    }

    var parentSummary: String? {
        guard let parentPID else {
            return nil
        }

        if let parentName, !parentName.isEmpty {
            return "\(parentName) (\(parentPID))"
        }

        return "\(parentPID)"
    }

    private var executableName: String {
        URL(fileURLWithPath: commandPath).lastPathComponent.nilIfEmpty ?? name
    }

    private var appBundleName: String? {
        let root = storagePath.flatMap(Self.appBundleRoot) ?? Self.appBundleRoot(for: commandPath)
        return root.flatMap { URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent.nilIfEmpty }
    }

    private var xpcServiceName: String? {
        pathComponent(endingWith: ".xpc")?.deletingSuffix(".xpc")
    }

    private var frameworkName: String? {
        pathComponent(endingWith: ".framework")?.deletingSuffix(".framework")
    }

    private var applicationSupportOwner: String? {
        let components = URL(fileURLWithPath: commandPath).pathComponents

        guard
            let index = components.firstIndex(of: "Application Support"),
            components.indices.contains(index + 1)
        else {
            return nil
        }

        return components[index + 1].nilIfEmpty
    }

    private var systemPathArea: String {
        if commandPath.contains("/PrivateFrameworks/") {
            return frameworkName.map { "\($0) private framework" } ?? "a private framework"
        }

        if commandPath.contains("/Frameworks/") {
            return frameworkName.map { "\($0) framework" } ?? "a framework"
        }

        if commandPath.hasPrefix("/usr/libexec/") {
            return "/usr/libexec"
        }

        if commandPath.hasPrefix("/usr/sbin/") || commandPath.hasPrefix("/usr/bin/") {
            return "/usr"
        }

        return "a protected system location"
    }

    private var isAppleSystemPath: Bool {
        commandPath.hasPrefix("/System/")
            || commandPath.hasPrefix("/usr/libexec/")
            || commandPath.hasPrefix("/usr/sbin/")
            || commandPath.hasPrefix("/usr/bin/")
            || commandPath.hasPrefix("/bin/")
            || commandPath.hasPrefix("/sbin/")
    }

    private var knownServiceInfo: (title: String, detail: String)? {
        Self.knownServices[executableName]
    }

    private var serviceReason: AppUsageReason? {
        switch executableName {
        case "fileproviderd":
            return AppUsageReason(
                title: "Cloud File Sync",
                detail: "Usually iCloud Drive or another File Provider syncing, downloading placeholders, reconciling folders, or responding to Finder/Spotlight file activity.",
                symbol: "icloud.and.arrow.up",
                tint: .blue
            )
        case "bird":
            return AppUsageReason(
                title: "iCloud Drive",
                detail: "iCloud Drive is moving, checking, or indexing files. This can climb after large file changes or when cloud placeholders hydrate.",
                symbol: "icloud",
                tint: .blue
            )
        case "cloudd":
            return AppUsageReason(
                title: "CloudKit / iCloud",
                detail: "Apple cloud sync for iCloud, app data, account-backed services, or apps using CloudKit.",
                symbol: "cloud",
                tint: .blue
            )
        case "mds", "mds_stores":
            return AppUsageReason(
                title: "Spotlight Indexing",
                detail: "Spotlight is indexing metadata. This often follows large file changes, new drives, app installs, or cloud sync activity.",
                symbol: "magnifyingglass",
                tint: .orange
            )
        case "WindowServer":
            return AppUsageReason(
                title: "Display / Window Load",
                detail: "macOS is compositing windows and display output. External displays, animations, screen recording, browser canvases, and many active windows can raise this.",
                symbol: "rectangle.on.rectangle",
                tint: .orange
            )
        case "nsurlsessiond":
            return AppUsageReason(
                title: "Background Transfer",
                detail: "macOS background networking used by apps and system services for downloads, uploads, updates, or sync.",
                symbol: "arrow.down.circle",
                tint: .blue
            )
        case "trustd":
            return AppUsageReason(
                title: "Certificate Checks",
                detail: "macOS is verifying secure connections or app signatures. This often appears alongside network-heavy apps.",
                symbol: "checkmark.shield",
                tint: .green
            )
        case "coreaudiod":
            return AppUsageReason(
                title: "Audio Engine",
                detail: "macOS audio service. Audio apps, plug-ins, interfaces, screen sharing, microphones, and playback can show up here.",
                symbol: "waveform",
                tint: .purple
            )
        default:
            return nil
        }
    }

    private func pathComponent(endingWith suffix: String) -> String? {
        URL(fileURLWithPath: commandPath)
            .pathComponents
            .first { $0.hasSuffix(suffix) }
    }

    private func helperSourceTitle(appName: String) -> String {
        let lowerName = executableName.lowercased()

        if lowerName.contains("renderer") {
            return "\(appName) renderer"
        }

        if lowerName.contains("gpu") {
            return "\(appName) GPU"
        }

        if lowerName.contains("crash") {
            return "\(appName) crash reporter"
        }

        if lowerName.contains("plugin") || lowerName.contains("plug-in") {
            return "\(appName) plug-in"
        }

        if lowerName.contains("network") {
            return "\(appName) networking"
        }

        if lowerName.contains("helper") {
            return "\(appName) helper"
        }

        return "\(appName) process"
    }

    private func helperDetail(appName: String) -> String {
        let lowerName = executableName.lowercased()
        let parent = parentName.map { " Parent: \($0)." } ?? ""

        if lowerName.contains("renderer") {
            return "Renderer process for \(appName). Browser-style and Electron apps use these for windows, tabs, web views, and page content.\(parent)"
        }

        if lowerName.contains("gpu") {
            return "Graphics helper for \(appName). It handles GPU-backed drawing, video, canvas, WebGL, or accelerated interface work.\(parent)"
        }

        if lowerName.contains("crash") {
            return "Crash reporting helper for \(appName). It normally stays quiet unless the app is collecting crash diagnostics.\(parent)"
        }

        if lowerName.contains("plugin") || lowerName.contains("plug-in") {
            return "Plug-in helper for \(appName). It is usually running app extensions, audio units, browser plug-ins, or isolated add-on code.\(parent)"
        }

        if lowerName.contains("network") {
            return "Networking helper for \(appName). Traffic and connections here should be counted as part of that app's network activity.\(parent)"
        }

        if lowerName.contains("helper") {
            return "Helper process inside \(appName). Activity here is usually part of that app, even when the helper has a generic name.\(parent)"
        }

        return "Process inside \(appName)'s app bundle. Activity here normally belongs to \(appName), even if macOS reports the executable separately.\(parent)"
    }

    static func impactSort(_ lhs: AppUsageMetric, _ rhs: AppUsageMetric) -> Bool {
        if lhs.powerImpactScore == rhs.powerImpactScore {
            return lhs.residentBytes > rhs.residentBytes
        }

        return lhs.powerImpactScore > rhs.powerImpactScore
    }

    private static func appBundleRoot(for path: String) -> String? {
        guard let range = path.range(of: ".app/") else {
            return path.hasSuffix(".app") ? path : nil
        }

        return String(path[..<range.upperBound].dropLast())
    }

    private static let knownServices: [String: (title: String, detail: String)] = [
        "fileproviderd": (
            "File Provider",
            "macOS File Provider service. It backs iCloud Drive and third-party cloud/storage providers, and often wakes up when Finder, Spotlight, or sync apps are indexing or moving files."
        ),
        "bird": (
            "iCloud Drive",
            "iCloud Drive sync service. High usage usually means files are uploading, downloading, reconciling, or being indexed."
        ),
        "cloudd": (
            "iCloud",
            "Apple cloud services daemon. It supports iCloud sync, CloudKit apps, and account-backed data."
        ),
        "mds": (
            "Spotlight",
            "Spotlight metadata server. CPU rises while macOS indexes files, apps, mail, or external drives."
        ),
        "mds_stores": (
            "Spotlight Index",
            "Spotlight index storage worker. It is usually paired with mds during indexing."
        ),
        "photoanalysisd": (
            "Photos Analysis",
            "Photos library analysis for people, scenes, memories, and visual search."
        ),
        "mediaanalysisd": (
            "Media Analysis",
            "Apple media analysis service for photos, videos, thumbnails, and visual intelligence features."
        ),
        "fseventsd": (
            "File Events",
            "macOS file change tracker. Finder, Spotlight, backup tools, and sync services depend on this."
        ),
        "nsurlsessiond": (
            "Background Downloads",
            "Apple background networking service used by apps and macOS for uploads, downloads, and sync tasks."
        ),
        "trustd": (
            "Certificate Trust",
            "Apple certificate and trust validation service used when apps verify secure connections and signatures."
        ),
        "syspolicyd": (
            "Gatekeeper",
            "macOS security policy service that checks app signatures, notarization, and launch safety."
        ),
        "accountsd": (
            "Internet Accounts",
            "Apple account service for iCloud, Mail, Calendar, Contacts, and other account-backed apps."
        ),
        "sharingd": (
            "Sharing",
            "Apple sharing service for AirDrop, Handoff, nearby devices, and local discovery."
        ),
        "rapportd": (
            "Continuity",
            "Apple Continuity service for nearby devices, Handoff, phone relay, and ecosystem discovery."
        ),
        "WindowServer": (
            "Window Server",
            "macOS display compositor. It reflects screen drawing, windows, animations, external displays, and GPU-backed UI work."
        ),
        "kernel_task": (
            "Kernel Task",
            "Core macOS kernel process. High usage can reflect drivers, I/O, memory pressure, or thermal management."
        ),
        "launchd": (
            "Launch Services",
            "macOS service supervisor. It starts and manages apps, daemons, agents, and background jobs."
        ),
        "cfprefsd": (
            "Preferences",
            "Apple preferences daemon. Apps use it to read and write settings."
        ),
        "distnoted": (
            "Notifications",
            "Distributed notification service used by apps and macOS components to broadcast local events."
        ),
        "logd": (
            "System Logging",
            "macOS unified logging daemon. It can rise when apps or system services are writing many logs."
        )
    ]
}

struct AppUsageReason: Identifiable {
    var id: String { "\(title)-\(detail)" }

    let title: String
    let detail: String
    let symbol: String
    let tint: Color
}

struct AppUsageHistorySample: Identifiable {
    var id: Date { timestamp }

    let timestamp: Date
    let cpuRatio: Double
    let memoryRatio: Double
    let networkBytesPerSecond: UInt64
    let networkTotalBytes: UInt64
    let fileAccessCount: Int
    let systemAccessCount: Int
    let powerImpactScore: Double
}

struct AppUsageHistory: Identifiable {
    let id: String
    private(set) var name: String
    private(set) var sourceText: String
    private(set) var samples: [AppUsageHistorySample]

    init(app: AppUsageMetric, timestamp: Date) {
        id = app.historyKey
        name = app.name
        sourceText = app.sourceText
        samples = [Self.sample(from: app, timestamp: timestamp)]
    }

    mutating func append(app: AppUsageMetric, timestamp: Date, limit: Int = 90) {
        name = app.name
        sourceText = app.sourceText
        samples.append(Self.sample(from: app, timestamp: timestamp))

        if samples.count > limit {
            samples.removeFirst(samples.count - limit)
        }
    }

    var latest: AppUsageHistorySample? {
        samples.last
    }

    var observedText: String {
        guard let first = samples.first?.timestamp, let last = samples.last?.timestamp else {
            return "No history yet"
        }

        let seconds = max(last.timeIntervalSince(first), 0)

        if seconds < 60 {
            return "\(Int(seconds))s observed"
        }

        return "\(Int(seconds / 60))m observed"
    }

    var peakCPUText: String {
        (samples.map(\.cpuRatio).max() ?? 0).percentString
    }

    var peakCPURatio: Double {
        samples.map(\.cpuRatio).max() ?? 0
    }

    var averageCPUText: String {
        average(samples.map(\.cpuRatio)).percentString
    }

    var peakMemoryText: String {
        (samples.map(\.memoryRatio).max() ?? 0).percentString
    }

    var peakMemoryRatio: Double {
        samples.map(\.memoryRatio).max() ?? 0
    }

    var averageMemoryText: String {
        average(samples.map(\.memoryRatio)).percentString
    }

    var transferredBytes: UInt64 {
        guard samples.count > 1 else {
            return 0
        }

        var total: UInt64 = 0
        var previous = samples[0].networkTotalBytes

        for sample in samples.dropFirst() {
            if sample.networkTotalBytes >= previous {
                total += sample.networkTotalBytes - previous
            }

            previous = sample.networkTotalBytes
        }

        return total
    }

    var transferredText: String {
        transferredBytes == 0 ? "-" : transferredBytes.byteString
    }

    var peakNetworkText: String {
        (samples.map(\.networkBytesPerSecond).max() ?? 0).rateString
    }

    var peakImpactScore: Double {
        samples.map(\.powerImpactScore).max() ?? 0
    }

    var cpuValues: [Double] {
        samples.map(\.cpuRatio)
    }

    var memoryValues: [Double] {
        samples.map(\.memoryRatio)
    }

    var networkValues: [Double] {
        let peak = max(samples.map(\.networkBytesPerSecond).max() ?? 0, 1)
        return samples.map { Double($0.networkBytesPerSecond) / Double(peak) }
    }

    private static func sample(from app: AppUsageMetric, timestamp: Date) -> AppUsageHistorySample {
        AppUsageHistorySample(
            timestamp: timestamp,
            cpuRatio: app.cpuRatio,
            memoryRatio: app.memoryRatio,
            networkBytesPerSecond: app.networkBytesPerSecond,
            networkTotalBytes: app.networkTotalBytes,
            fileAccessCount: app.fileAccessCount,
            systemAccessCount: app.systemAccessCount,
            powerImpactScore: app.powerImpactScore
        )
    }

    private func average(_ values: [Double]) -> Double {
        guard !values.isEmpty else {
            return 0
        }

        return values.reduce(0, +) / Double(values.count)
    }
}

private struct AppSampleOptions {
    let includeNetworkTraffic: Bool
    let includeAccessCounts: Bool

    static let full = AppSampleOptions(includeNetworkTraffic: true, includeAccessCounts: true)
    static let lightweight = AppSampleOptions(includeNetworkTraffic: false, includeAccessCounts: false)
}

struct RunningAppProfile: Sendable {
    let pid: Int
    let name: String
    let bundlePath: String?
    let executablePath: String?
    let isVisible: Bool
}

private struct SmartBatteryDetails {
    let cycleCount: Int?
    let temperatureCelsius: Double?
    let powerWatts: Double?

    static let empty = SmartBatteryDetails(cycleCount: nil, temperatureCelsius: nil, powerWatts: nil)
}

struct StorageItemMetric: Identifiable {
    let id: String
    let path: String
    let name: String
    let folderName: String
    let bytes: UInt64
    let lastAccessedAt: Date?
    let modifiedAt: Date?

    var sizeText: String {
        bytes.byteString
    }

    var activityDate: Date? {
        lastAccessedAt ?? modifiedAt
    }

    var activityText: String {
        guard let activityDate else { return "Last use unknown" }
        return "Last touched \(activityDate.relativeAgeText)"
    }

    var detailText: String {
        "\(folderName) • \(activityText)"
    }

    var idleDays: Int? {
        guard let activityDate else { return nil }
        return Calendar.current.dateComponents([.day], from: activityDate, to: Date()).day
    }

    var cleanupScore: Double {
        let sizeScore = Double(bytes) / Double(1_000_000_000)
        let idleScore = Double(min(max(idleDays ?? 0, 0), 365)) / 60.0
        return sizeScore * (1.0 + idleScore)
    }
}

struct StorageAnalysisMetric {
    let categories: [StorageCategoryMetric]
    let folderHotspots: [StorageFolderMetric]
    let staleFiles: [StorageItemMetric]
    let scannedFileCount: Int
    let scannedBytes: UInt64

    var reviewBytes: UInt64 {
        categories
            .filter { $0.kind.reviewPriority > 0 }
            .reduce(0) { $0 + $1.bytes }
    }

    var scannedText: String {
        "\(scannedFileCount.formatted()) files"
    }

    static let empty = StorageAnalysisMetric(
        categories: [],
        folderHotspots: [],
        staleFiles: [],
        scannedFileCount: 0,
        scannedBytes: 0
    )
}

struct StorageCategoryMetric: Identifiable {
    var id: String { kind.rawValue }

    let kind: StorageCategoryKind
    let bytes: UInt64
    let fileCount: Int

    var title: String {
        kind.title
    }

    var detailText: String {
        "\(fileCount.formatted()) files • \(kind.guidance)"
    }
}

struct StorageFolderMetric: Identifiable {
    let id: String
    let path: String
    let name: String
    let kind: StorageCategoryKind
    let bytes: UInt64
    let fileCount: Int
    let lastActivity: Date?

    var sizeText: String {
        bytes.byteString
    }

    var activityText: String {
        guard let lastActivity else {
            return "Activity unknown"
        }

        return lastActivity.relativeAgeText
    }

    var detailText: String {
        "\(kind.title) • \(fileCount.formatted()) files • \(activityText)"
    }
}

enum StorageCategoryKind: String {
    case downloads
    case documents
    case media
    case caches
    case appSupport
    case containers
    case developer
    case logs
    case packageBuilds
    case other

    var title: String {
        switch self {
        case .downloads:
            return "Downloads"
        case .documents:
            return "Documents"
        case .media:
            return "Media"
        case .caches:
            return "Caches"
        case .appSupport:
            return "App Support"
        case .containers:
            return "Containers"
        case .developer:
            return "Developer"
        case .logs:
            return "Logs"
        case .packageBuilds:
            return "Build / Packages"
        case .other:
            return "Other"
        }
    }

    var guidance: String {
        switch self {
        case .caches:
            return "Often rebuildable"
        case .logs:
            return "Usually reviewable"
        case .developer, .packageBuilds:
            return "Build artifacts and dependencies"
        case .downloads:
            return "Usually safe to review"
        case .appSupport, .containers:
            return "App data, remove carefully"
        case .documents, .media:
            return "Personal files"
        case .other:
            return "Review manually"
        }
    }

    var reviewPriority: Int {
        switch self {
        case .caches, .logs, .developer, .packageBuilds, .downloads:
            return 2
        case .appSupport, .containers:
            return 1
        case .documents, .media, .other:
            return 0
        }
    }
}

struct SensorStatusMetric {
    let thermalState: String
    let thermalDetail: String
    let lowPowerMode: Bool
    let uptime: TimeInterval
    let activeCoreCount: Int
    let coreCount: Int
    let osVersion: String
    let hostName: String
    let powerAdapterWatts: Int?

    var readings: [SensorReadingMetric] {
        var values = [
            SensorReadingMetric(label: "Thermal", value: thermalState, detail: thermalDetail, symbol: "thermometer.medium", tint: .orange),
            SensorReadingMetric(label: "Power Mode", value: lowPowerMode ? "Low Power" : "Standard", detail: lowPowerMode ? "macOS is reducing energy use" : "Normal performance mode", symbol: "leaf", tint: lowPowerMode ? .green : .secondary),
            SensorReadingMetric(label: "Uptime", value: uptime.uptimeText, detail: "Time since last boot", symbol: "timer", tint: .cyan),
            SensorReadingMetric(label: "CPU Cores", value: "\(activeCoreCount)/\(coreCount)", detail: "Active logical cores", symbol: "cpu", tint: .orange)
        ]

        if let powerAdapterWatts {
            values.append(
                SensorReadingMetric(label: "Adapter", value: "\(powerAdapterWatts) W", detail: "Connected power adapter", symbol: "powerplug", tint: .green)
            )
        }

        values.append(
            SensorReadingMetric(label: "macOS", value: osVersion, detail: hostName, symbol: "desktopcomputer", tint: .indigo)
        )

        return values
    }

    static let placeholder = SensorStatusMetric(
        thermalState: "Unknown",
        thermalDetail: "Waiting for system status",
        lowPowerMode: false,
        uptime: 0,
        activeCoreCount: ProcessInfo.processInfo.activeProcessorCount,
        coreCount: ProcessInfo.processInfo.processorCount,
        osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
        hostName: Host.current().localizedName ?? "This Mac",
        powerAdapterWatts: nil
    )
}

struct SensorReadingMetric: Identifiable {
    var id: String { label }

    let label: String
    let value: String
    let detail: String
    let symbol: String
    let tint: Color
}

struct DeepMetrics {
    let topApps: [AppUsageMetric]
    let storageCandidates: [StorageItemMetric]
    let storageAnalysis: StorageAnalysisMetric
    let connections: [NetworkConnectionMetric]
    let appStorageByPath: [String: UInt64]

    static let empty = DeepMetrics(topApps: [], storageCandidates: [], storageAnalysis: .empty, connections: [], appStorageByPath: [:])

    func replacingLive(topApps: [AppUsageMetric], connections: [NetworkConnectionMetric]) -> DeepMetrics {
        DeepMetrics(
            topApps: topApps,
            storageCandidates: storageCandidates,
            storageAnalysis: storageAnalysis,
            connections: connections,
            appStorageByPath: appStorageByPath
        )
    }

    static func visibleFallback(from profiles: [RunningAppProfile]) -> DeepMetrics {
        DeepMetrics(
            topApps: profiles
                .filter(\.isVisible)
                .map { profile in
                    AppUsageMetric(
                        id: profile.pid,
                        pid: profile.pid,
                        name: profile.name,
                        commandPath: profile.executablePath ?? profile.bundlePath ?? profile.name,
                        residentBytes: 0,
                        cpuPercent: 0,
                        isVisible: true,
                        networkConnectionCount: 0,
                        storageBytes: nil,
                        storagePath: profile.bundlePath ?? profile.executablePath
                    )
                },
            storageCandidates: [],
            storageAnalysis: .empty,
            connections: [],
            appStorageByPath: [:]
        )
    }
}

private struct AppScanResult {
    let apps: [AppUsageMetric]
    let storageByPath: [String: UInt64]
}

private struct ProcessNetworkTraffic {
    var downloadBytesPerSecond: UInt64
    var uploadBytesPerSecond: UInt64
    var totalDownloadBytes: UInt64
    var totalUploadBytes: UInt64

    static let zero = ProcessNetworkTraffic(
        downloadBytesPerSecond: 0,
        uploadBytesPerSecond: 0,
        totalDownloadBytes: 0,
        totalUploadBytes: 0
    )

    mutating func add(_ other: ProcessNetworkTraffic) {
        downloadBytesPerSecond += other.downloadBytesPerSecond
        uploadBytesPerSecond += other.uploadBytesPerSecond
        totalDownloadBytes += other.totalDownloadBytes
        totalUploadBytes += other.totalUploadBytes
    }
}

private struct NetworkByteSample {
    var downloadBytes: UInt64
    var uploadBytes: UInt64

    static let zero = NetworkByteSample(downloadBytes: 0, uploadBytes: 0)

    mutating func add(_ other: NetworkByteSample) {
        downloadBytes += other.downloadBytes
        uploadBytes += other.uploadBytes
    }
}

private struct ProcessAccessCounts {
    var fileCount: Int
    var systemCount: Int

    static let zero = ProcessAccessCounts(fileCount: 0, systemCount: 0)

    mutating func add(_ other: ProcessAccessCounts) {
        fileCount += other.fileCount
        systemCount += other.systemCount
    }
}

final class MetricsSampler {
    private var previousCPU: CPUTicks?
    private var previousNetwork: NetworkCountersSample?
    private var cpuHistory: [Double] = []
    private var memoryHistory: [Double] = []
    private var cachedBatteryDetails = SmartBatteryDetails.empty
    private var cachedSmartBatteryAt: Date?
    private var cachedAdapterWatts: Int?
    private var cachedPowerAdapterAt: Date?
    private let slowSensorRefreshInterval: TimeInterval = 30

    func capture(deepMetrics: DeepMetrics = .empty) -> SystemSnapshot {
        let disk = sampleDisk()
        let cpu = sampleCPU()
        let memory = sampleMemory()
        let battery = sampleBattery()

        appendHistory(&cpuHistory, value: cpu.usageRatio ?? cpuHistory.last ?? 0, limit: 44)
        appendHistory(&memoryHistory, value: memory.usedRatio, limit: 44)

        let network = sampleNetwork(connections: deepMetrics.connections)

        return SystemSnapshot(
            disk: disk,
            cpu: cpu,
            memory: memory,
            battery: battery,
            network: network,
            gpu: GPUMetric(devices: []),
            topApps: deepMetrics.topApps,
            storageCandidates: deepMetrics.storageCandidates,
            storageAnalysis: deepMetrics.storageAnalysis,
            sensors: sampleSensors(),
            cpuHistory: cpuHistory,
            memoryHistory: memoryHistory,
            updatedAt: Date()
        )
    }

    func scanDeepMetrics(appProfiles: [RunningAppProfile], existingStorageByPath: [String: UInt64]) -> DeepMetrics {
        let connections = sampleNetworkConnections()
        let appScan = sampleTopApps(
            appProfiles: appProfiles,
            connections: connections,
            existingStorageByPath: existingStorageByPath,
            existingApps: [],
            allowStorageScan: true,
            options: .full
        )
        let storageAnalysis = sampleStorageAnalysis()

        return DeepMetrics(
            topApps: appScan.apps,
            storageCandidates: storageAnalysis.staleFiles,
            storageAnalysis: storageAnalysis,
            connections: connections,
            appStorageByPath: appScan.storageByPath
        )
    }

    func scanLiveMetrics(
        existingStorageCandidates: [StorageItemMetric],
        existingStorageAnalysis: StorageAnalysisMetric,
        existingStorageByPath: [String: UInt64],
        existingApps: [AppUsageMetric],
        existingConnections: [NetworkConnectionMetric],
        appProfiles: [RunningAppProfile],
        includeExpensiveMetrics: Bool
    ) -> DeepMetrics {
        let connections = includeExpensiveMetrics ? sampleNetworkConnections() : existingConnections
        let appScan = sampleTopApps(
            appProfiles: appProfiles,
            connections: connections,
            existingStorageByPath: existingStorageByPath,
            existingApps: existingApps,
            allowStorageScan: false,
            options: AppSampleOptions(
                includeNetworkTraffic: includeExpensiveMetrics,
                includeAccessCounts: false
            )
        )

        return DeepMetrics(
            topApps: appScan.apps,
            storageCandidates: existingStorageCandidates,
            storageAnalysis: existingStorageAnalysis,
            connections: connections,
            appStorageByPath: appScan.storageByPath
        )
    }

    private func sampleDisk() -> DiskMetric {
        let homeURL = URL(fileURLWithPath: NSHomeDirectory())
        let keys: Set<URLResourceKey> = [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey
        ]

        guard let values = try? homeURL.resourceValues(forKeys: keys) else {
            return DiskMetric(totalBytes: 0, freeBytes: 0)
        }

        let total = UInt64(max(values.volumeTotalCapacity ?? 0, 0))
        let importantFree = values.volumeAvailableCapacityForImportantUsage.map { UInt64(max($0, 0)) }
        let regularFree = values.volumeAvailableCapacity.map { UInt64(max($0, 0)) }
        let free = importantFree ?? regularFree ?? 0

        return DiskMetric(totalBytes: total, freeBytes: min(free, total))
    }

    private func sampleCPU() -> CPUMetric {
        guard let current = readCPUTicks() else {
            return CPUMetric(
                usageRatio: nil,
                coreCount: ProcessInfo.processInfo.processorCount,
                activeCoreCount: ProcessInfo.processInfo.activeProcessorCount
            )
        }

        defer {
            previousCPU = current
        }

        guard let previousCPU else {
            return CPUMetric(
                usageRatio: nil,
                coreCount: ProcessInfo.processInfo.processorCount,
                activeCoreCount: ProcessInfo.processInfo.activeProcessorCount
            )
        }

        let user = current.user.saturatingDifference(from: previousCPU.user)
        let system = current.system.saturatingDifference(from: previousCPU.system)
        let nice = current.nice.saturatingDifference(from: previousCPU.nice)
        let idle = current.idle.saturatingDifference(from: previousCPU.idle)
        let active = user + system + nice
        let total = active + idle
        let ratio = total == 0 ? nil : Double(active) / Double(total)

        return CPUMetric(
            usageRatio: ratio.map { min(max($0, 0), 1) },
            coreCount: ProcessInfo.processInfo.processorCount,
            activeCoreCount: ProcessInfo.processInfo.activeProcessorCount
        )
    }

    private func sampleMemory() -> MemoryMetric {
        var pageSize: vm_size_t = 0
        host_page_size(mach_host_self(), &pageSize)

        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)

        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { reboundPointer in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, reboundPointer, &count)
            }
        }

        guard result == KERN_SUCCESS else {
            return MemoryMetric(
                totalBytes: ProcessInfo.processInfo.physicalMemory,
                appBytes: 0,
                wiredBytes: 0,
                compressedBytes: 0,
                cachedBytes: 0,
                freeBytes: 0
            )
        }

        let page = UInt64(pageSize)
        let app = UInt64(stats.active_count) * page
        let wired = UInt64(stats.wire_count) * page
        let compressed = UInt64(stats.compressor_page_count) * page
        let cached = (UInt64(stats.inactive_count) + UInt64(stats.speculative_count)) * page
        let free = UInt64(stats.free_count) * page

        return MemoryMetric(
            totalBytes: ProcessInfo.processInfo.physicalMemory,
            appBytes: app,
            wiredBytes: wired,
            compressedBytes: compressed,
            cachedBytes: cached,
            freeBytes: free
        )
    }

    private func sampleBattery() -> BatteryMetric {
        let smartBattery = cachedSmartBatteryDetails()
        let adapterWatts = cachedPowerAdapterWatts()
        let info = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let sources = IOPSCopyPowerSourcesList(info).takeRetainedValue() as [CFTypeRef]

        for source in sources {
            guard
                let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                let currentCapacity = description[kIOPSCurrentCapacityKey as String] as? Int,
                let maxCapacity = description[kIOPSMaxCapacityKey as String] as? Int,
                maxCapacity > 0
            else {
                continue
            }

            let powerState = description[kIOPSPowerSourceStateKey as String] as? String
            let isCharging = (description[kIOPSIsChargingKey as String] as? Bool) ?? false
            let isPluggedIn = powerState == kIOPSACPowerValue
            let ratio = Double(currentCapacity) / Double(maxCapacity)
            let timeToEmpty = positiveMinutes(description[kIOPSTimeToEmptyKey as String] as? Int)
            let timeToFull = positiveMinutes(description[kIOPSTimeToFullChargeKey as String] as? Int)
            let health = description[kIOPSBatteryHealthKey as String] as? String

            return BatteryMetric(
                levelRatio: min(max(ratio, 0), 1),
                isCharging: isCharging,
                isPluggedIn: isPluggedIn,
                timeToEmptyMinutes: timeToEmpty,
                timeToFullMinutes: timeToFull,
                health: health,
                cycleCount: smartBattery.cycleCount,
                temperatureCelsius: smartBattery.temperatureCelsius,
                powerWatts: smartBattery.powerWatts,
                adapterWatts: adapterWatts
            )
        }

        return BatteryMetric(
            levelRatio: nil,
            isCharging: false,
            isPluggedIn: false,
            timeToEmptyMinutes: nil,
            timeToFullMinutes: nil,
            health: nil,
            cycleCount: smartBattery.cycleCount,
            temperatureCelsius: smartBattery.temperatureCelsius,
            powerWatts: smartBattery.powerWatts,
            adapterWatts: adapterWatts
        )
    }

    private func sampleNetwork(connections: [NetworkConnectionMetric]) -> NetworkMetric {
        let current = readNetworkCounters()

        defer {
            previousNetwork = current
        }

        let elapsed = max(current.timestamp.timeIntervalSince(previousNetwork?.timestamp ?? current.timestamp), 0.001)
        var totalDown: UInt64 = 0
        var totalUp: UInt64 = 0
        var interfaces: [NetworkInterfaceMetric] = []

        for counter in current.interfaces.values {
            let previous = previousNetwork?.interfaces[counter.name]
            let down = previous.map { UInt64(Double(counter.received.saturatingDifference(from: $0.received)) / elapsed) } ?? 0
            let up = previous.map { UInt64(Double(counter.sent.saturatingDifference(from: $0.sent)) / elapsed) } ?? 0

            totalDown += down
            totalUp += up

            interfaces.append(
                NetworkInterfaceMetric(
                    id: counter.name,
                    name: counter.name,
                    displayName: displayName(forInterface: counter.name),
                    downloadBytesPerSecond: down,
                    uploadBytesPerSecond: up,
                    totalReceivedBytes: counter.received,
                    totalSentBytes: counter.sent,
                    linkSpeedBitsPerSecond: counter.baudrate == 0 ? nil : counter.baudrate
                )
            )
        }

        interfaces.sort {
            let lhsTraffic = $0.downloadBytesPerSecond + $0.uploadBytesPerSecond
            let rhsTraffic = $1.downloadBytesPerSecond + $1.uploadBytesPerSecond

            if lhsTraffic == rhsTraffic {
                return $0.name < $1.name
            }

            return lhsTraffic > rhsTraffic
        }

        return NetworkMetric(
            downloadBytesPerSecond: totalDown,
            uploadBytesPerSecond: totalUp,
            interfaces: interfaces,
            connections: connections
        )
    }

    private func sampleGPU() -> GPUMetric {
        let devices = MTLCopyAllDevices().map { device in
            GPUDeviceMetric(
                id: device.name,
                name: device.name,
                isLowPower: device.isLowPower,
                isRemovable: device.isRemovable,
                hasUnifiedMemory: device.hasUnifiedMemory,
                recommendedMaxWorkingSetBytes: device.recommendedMaxWorkingSetSize,
                currentAllocatedBytes: UInt64(device.currentAllocatedSize)
            )
        }

        return GPUMetric(devices: devices)
    }

    private func sampleTopApps(
        appProfiles: [RunningAppProfile],
        connections: [NetworkConnectionMetric],
        existingStorageByPath: [String: UInt64],
        existingApps: [AppUsageMetric],
        allowStorageScan: Bool,
        options: AppSampleOptions
    ) -> AppScanResult {
        let connectionCounts = options.includeNetworkTraffic ? Dictionary(grouping: connections, by: \.pid).mapValues(\.count) : [:]
        let networkTrafficByPID = options.includeNetworkTraffic ? sampleNetworkTrafficByPID() : [:]
        let accessCountsByPID = options.includeAccessCounts ? sampleAccessCountsByPID() : [:]
        var storageByPath = existingStorageByPath

        guard let output = runCommand("/bin/ps", arguments: ["-axo", "pid=,ppid=,user=,rss=,pcpu=,comm="]) else {
            let fallback = fallbackAppScan(
                appProfiles: appProfiles,
                connectionCounts: connectionCounts,
                networkTrafficByPID: networkTrafficByPID,
                accessCountsByPID: accessCountsByPID,
                storageByPath: &storageByPath,
                allowStorageScan: allowStorageScan
            )

            return AppScanResult(
                apps: mergeSampledDetails(
                    fallback.apps,
                    existingApps: existingApps,
                    options: options
                ),
                storageByPath: fallback.storageByPath
            )
        }

        let profilesByPID = Dictionary(uniqueKeysWithValues: appProfiles.map { ($0.pid, $0) })
        let visibleProfilesByBundle = appProfiles
            .filter { $0.isVisible && $0.bundlePath != nil }
            .sorted { ($0.bundlePath ?? "").count > ($1.bundlePath ?? "").count }
        let visiblePIDs = Set(appProfiles.filter(\.isVisible).map(\.pid))
        let visibleBundlePaths = Set(appProfiles.compactMap { $0.isVisible ? $0.bundlePath : nil })

        let parsedProcesses = output
            .split(separator: "\n")
            .compactMap(parseProcessLine)
        let processNamesByPID = Dictionary(uniqueKeysWithValues: parsedProcesses.map { ($0.pid, $0.name) })
        var processApps: [AppUsageMetric] = []

        for parsedApp in parsedProcesses {
            let profile = profilesByPID[parsedApp.pid] ?? matchingProfile(for: parsedApp.commandPath, in: visibleProfilesByBundle)
            let enrichedApp = enrich(
                parsedApp,
                profile: profile,
                parentName: parsedApp.parentPID.flatMap { processNamesByPID[$0] },
                connectionCount: connectionCounts[parsedApp.pid] ?? 0,
                networkTraffic: networkTrafficByPID[parsedApp.pid] ?? .zero,
                accessCounts: accessCountsByPID[parsedApp.pid] ?? .zero,
                storageByPath: &storageByPath,
                allowStorageScan: allowStorageScan
            )

            processApps.append(enrichedApp)
        }

        let representedPIDs = Set(processApps.map { $0.pid })
        let missingVisibleApps = appProfiles
            .filter { $0.isVisible && !representedPIDs.contains($0.pid) }
            .map { profile in
                enrich(
                    AppUsageMetric(
                        id: profile.pid,
                        pid: profile.pid,
                        name: profile.name,
                        commandPath: profile.executablePath ?? profile.bundlePath ?? profile.name,
                        residentBytes: 0,
                        cpuPercent: 0
                    ),
                    profile: profile,
                    parentName: nil,
                    connectionCount: connectionCounts[profile.pid] ?? 0,
                    networkTraffic: networkTrafficByPID[profile.pid] ?? .zero,
                    accessCounts: accessCountsByPID[profile.pid] ?? .zero,
                    storageByPath: &storageByPath,
                    allowStorageScan: allowStorageScan
                )
            }

        processApps.append(contentsOf: missingVisibleApps)

        let visibleAppTotals = aggregateVisibleApps(
            from: processApps,
            profiles: appProfiles.filter(\.isVisible),
            storageByPath: &storageByPath,
            allowStorageScan: allowStorageScan
        )

        let relevantBackgroundApps = processApps
            .filter {
                shouldShowBackgroundProcess(
                    $0,
                    visiblePIDs: visiblePIDs,
                    visibleBundlePaths: visibleBundlePaths
                )
            }
            .sorted(by: AppUsageMetric.impactSort)
            .prefix(140)
            .map { $0 }

        let sortedApps = (visibleAppTotals + relevantBackgroundApps)
            .sorted(by: AppUsageMetric.impactSort)

        return AppScanResult(
            apps: mergeSampledDetails(
                sortedApps,
                existingApps: existingApps,
                options: options
            ),
            storageByPath: storageByPath
        )
    }

    private func mergeSampledDetails(
        _ apps: [AppUsageMetric],
        existingApps: [AppUsageMetric],
        options: AppSampleOptions
    ) -> [AppUsageMetric] {
        guard !existingApps.isEmpty, (!options.includeNetworkTraffic || !options.includeAccessCounts) else {
            return apps
        }

        let existingByID = Dictionary(existingApps.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let existingByPIDAndVisibility = Dictionary(existingApps.map { ("\($0.pid)-\($0.isVisible)", $0) }, uniquingKeysWith: { first, _ in first })
        let existingByHistoryKey = Dictionary(existingApps.map { ($0.historyKey, $0) }, uniquingKeysWith: { first, _ in first })

        return apps.map { app in
            let previous = existingByID[app.id]
                ?? existingByPIDAndVisibility["\(app.pid)-\(app.isVisible)"]
                ?? existingByHistoryKey[app.historyKey]

            return app.preservingSampledDetails(
                from: previous,
                includeNetwork: options.includeNetworkTraffic,
                includeAccess: options.includeAccessCounts
            )
        }
    }

    private func fallbackAppScan(
        appProfiles: [RunningAppProfile],
        connectionCounts: [Int: Int],
        networkTrafficByPID: [Int: ProcessNetworkTraffic],
        accessCountsByPID: [Int: ProcessAccessCounts],
        storageByPath: inout [String: UInt64],
        allowStorageScan: Bool
    ) -> AppScanResult {
        let apps = appProfiles
            .filter(\.isVisible)
            .map { profile in
                enrich(
                    AppUsageMetric(
                        id: profile.pid,
                        pid: profile.pid,
                        name: profile.name,
                        commandPath: profile.executablePath ?? profile.bundlePath ?? profile.name,
                        residentBytes: 0,
                        cpuPercent: 0
                    ),
                    profile: profile,
                    parentName: nil,
                    connectionCount: connectionCounts[profile.pid] ?? 0,
                    networkTraffic: networkTrafficByPID[profile.pid] ?? .zero,
                    accessCounts: accessCountsByPID[profile.pid] ?? .zero,
                    storageByPath: &storageByPath,
                    allowStorageScan: allowStorageScan
                )
            }
            .sorted(by: AppUsageMetric.impactSort)

        return AppScanResult(apps: apps, storageByPath: storageByPath)
    }

    private func enrich(
        _ app: AppUsageMetric,
        profile: RunningAppProfile?,
        parentName: String?,
        connectionCount: Int,
        networkTraffic: ProcessNetworkTraffic,
        accessCounts: ProcessAccessCounts,
        storageByPath: inout [String: UInt64],
        allowStorageScan: Bool
    ) -> AppUsageMetric {
        let storagePath = storagePath(for: app, profile: profile)
        let storageBytes = storagePath.flatMap { path -> UInt64? in
            if let cached = storageByPath[path] {
                return cached
            }

            guard allowStorageScan, let bytes = storageFootprintBytes(atPath: path) else {
                return nil
            }

            storageByPath[path] = bytes
            return bytes
        }

        let isMainAppProcess = app.pid == profile?.pid

        return AppUsageMetric(
            id: app.pid,
            pid: app.pid,
            parentPID: app.parentPID,
            name: app.pid == profile?.pid ? profile?.name.nilIfEmpty ?? app.name : app.name,
            commandPath: isMainAppProcess ? profile?.executablePath ?? app.commandPath : app.commandPath,
            ownerName: app.ownerName,
            parentName: parentName ?? app.parentName,
            bundleIdentifier: bundleIdentifier(for: storagePath),
            residentBytes: app.residentBytes,
            cpuPercent: app.cpuPercent,
            isVisible: false,
            networkConnectionCount: connectionCount,
            networkDownloadBytesPerSecond: networkTraffic.downloadBytesPerSecond,
            networkUploadBytesPerSecond: networkTraffic.uploadBytesPerSecond,
            networkTotalDownloadBytes: networkTraffic.totalDownloadBytes,
            networkTotalUploadBytes: networkTraffic.totalUploadBytes,
            fileAccessCount: accessCounts.fileCount,
            systemAccessCount: accessCounts.systemCount,
            storageBytes: storageBytes,
            storagePath: storagePath
        )
    }

    private func aggregateVisibleApps(
        from processApps: [AppUsageMetric],
        profiles: [RunningAppProfile],
        storageByPath: inout [String: UInt64],
        allowStorageScan: Bool
    ) -> [AppUsageMetric] {
        profiles.map { profile in
            let children = processApps.filter { app in
                if app.pid == profile.pid {
                    return true
                }

                guard let bundlePath = profile.bundlePath else {
                    return false
                }

                return app.storagePath == bundlePath || app.commandPath.hasPrefix(bundlePath + "/")
            }

            let storagePath = profile.bundlePath ?? profile.executablePath
            let storageBytes = storagePath.flatMap { path -> UInt64? in
                if let cached = storageByPath[path] {
                    return cached
                }

                guard allowStorageScan, let bytes = storageFootprintBytes(atPath: path) else {
                    return nil
                }

                storageByPath[path] = bytes
                return bytes
            }

            return AppUsageMetric(
                id: -profile.pid,
                pid: profile.pid,
                parentPID: nil,
                name: profile.name,
                commandPath: profile.executablePath ?? profile.bundlePath ?? profile.name,
                ownerName: children.first?.ownerName,
                parentName: nil,
                bundleIdentifier: bundleIdentifier(for: storagePath),
                residentBytes: children.reduce(UInt64(0)) { $0 + $1.residentBytes },
                cpuPercent: children.reduce(0) { $0 + $1.cpuPercent },
                isVisible: true,
                processCount: max(children.count, 1),
                networkConnectionCount: children.reduce(0) { $0 + $1.networkConnectionCount },
                networkDownloadBytesPerSecond: children.reduce(UInt64(0)) { $0 + $1.networkDownloadBytesPerSecond },
                networkUploadBytesPerSecond: children.reduce(UInt64(0)) { $0 + $1.networkUploadBytesPerSecond },
                networkTotalDownloadBytes: children.reduce(UInt64(0)) { $0 + $1.networkTotalDownloadBytes },
                networkTotalUploadBytes: children.reduce(UInt64(0)) { $0 + $1.networkTotalUploadBytes },
                fileAccessCount: children.reduce(0) { $0 + $1.fileAccessCount },
                systemAccessCount: children.reduce(0) { $0 + $1.systemAccessCount },
                storageBytes: storageBytes,
                storagePath: storagePath
            )
        }
        .sorted(by: AppUsageMetric.impactSort)
    }

    private func shouldShowBackgroundProcess(
        _ app: AppUsageMetric,
        visiblePIDs: Set<Int>,
        visibleBundlePaths: Set<String>
    ) -> Bool {
        if visiblePIDs.contains(app.pid) {
            return false
        }

        if let storagePath = app.storagePath, visibleBundlePaths.contains(storagePath) {
            return false
        }

        return app.residentBytes > 12_000_000
            || app.cpuPercent >= 0.2
            || app.networkConnectionCount > 0
            || app.networkBytesPerSecond > 0
            || app.networkTotalBytes > 0
            || app.fileAccessCount >= 20
            || app.systemAccessCount >= 20
    }

    private func matchingProfile(for commandPath: String, in profiles: [RunningAppProfile]) -> RunningAppProfile? {
        profiles.first { profile in
            guard let bundlePath = profile.bundlePath else {
                return false
            }

            return commandPath.hasPrefix(bundlePath + "/")
        }
    }

    private func storagePath(for app: AppUsageMetric, profile: RunningAppProfile?) -> String? {
        if let bundlePath = profile?.bundlePath {
            return bundlePath
        }

        if let executablePath = profile?.executablePath {
            return appBundleRoot(for: executablePath) ?? executablePath
        }

        return appBundleRoot(for: app.commandPath) ?? app.commandPath.nilIfEmpty
    }

    private func appBundleRoot(for path: String) -> String? {
        guard let range = path.range(of: ".app/") else {
            return path.hasSuffix(".app") ? path : nil
        }

        return String(path[..<range.upperBound].dropLast())
    }

    private func bundleIdentifier(for path: String?) -> String? {
        guard let path else {
            return nil
        }

        let bundlePath = appBundleRoot(for: path) ?? path

        guard bundlePath.hasSuffix(".app") else {
            return nil
        }

        return Bundle(url: URL(fileURLWithPath: bundlePath))?.bundleIdentifier
    }

    private func storageFootprintBytes(atPath path: String) -> UInt64? {
        let url = URL(fileURLWithPath: path)
        var isDirectory: ObjCBool = false

        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else {
            return nil
        }

        if isDirectory.boolValue {
            return directoryAllocatedSize(url, maxItems: 1_800)
        }

        let values = try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .fileSizeKey])
        let bytes = values?.totalFileAllocatedSize ?? values?.fileAllocatedSize ?? values?.fileSize
        return bytes.map { UInt64(max($0, 0)) }
    }

    private func directoryAllocatedSize(_ root: URL, maxItems: Int) -> UInt64? {
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .fileSizeKey, .isRegularFileKey]
        var total: UInt64 = 0
        var scanned = 0

        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        while let url = enumerator.nextObject() as? URL {
            scanned += 1

            if scanned > maxItems {
                break
            }

            guard
                let values = try? url.resourceValues(forKeys: Set(keys)),
                values.isRegularFile == true
            else {
                continue
            }

            let bytes = values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? values.fileSize ?? 0
            total += UInt64(max(bytes, 0))
        }

        return total == 0 ? nil : total
    }

    private func sampleStorageAnalysis() -> StorageAnalysisMetric {
        let keys: [URLResourceKey] = [
            .isRegularFileKey,
            .totalFileAllocatedSizeKey,
            .fileAllocatedSizeKey,
            .fileSizeKey,
            .contentAccessDateKey,
            .contentModificationDateKey
        ]
        var categoryAccumulators: [StorageCategoryKind: StorageCategoryAccumulator] = [:]
        var folderAccumulators: [String: StorageFolderAccumulator] = [:]
        var staleFiles: [StorageItemMetric] = []
        var scannedFiles = 0
        var scannedBytes: UInt64 = 0
        var shouldStop = false
        let maxFiles = 120_000

        for root in storageScanRoots() {
            if shouldStop {
                break
            }

            let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: keys,
                options: [.skipsPackageDescendants]
            ) { _, _ in
                true
            }

            while let fileURL = enumerator?.nextObject() as? URL {
                if scannedFiles >= maxFiles {
                    shouldStop = true
                    break
                }

                guard
                    let values = try? fileURL.resourceValues(forKeys: Set(keys)),
                    values.isRegularFile == true
                else {
                    continue
                }

                scannedFiles += 1
                let bytes = UInt64(max(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? values.fileSize ?? 0, 0))
                guard bytes > 0 else {
                    continue
                }

                scannedBytes += bytes
                let kind = storageCategory(for: fileURL, root: root)
                let activityDate = values.contentAccessDate ?? values.contentModificationDate
                categoryAccumulators[kind, default: StorageCategoryAccumulator(kind: kind)].add(bytes: bytes)

                for folderURL in storageFolders(for: fileURL, root: root) {
                    let path = folderURL.path
                    folderAccumulators[path, default: StorageFolderAccumulator(path: path, name: folderURL.lastPathComponent.nilIfEmpty ?? path, kind: kind)]
                        .add(bytes: bytes, activityDate: activityDate)
                }

                let item = StorageItemMetric(
                    id: fileURL.path,
                    path: fileURL.path,
                    name: fileURL.lastPathComponent,
                    folderName: friendlyFolderName(root),
                    bytes: bytes,
                    lastAccessedAt: values.contentAccessDate,
                    modifiedAt: values.contentModificationDate
                )

                if isReviewCandidate(item: item, kind: kind) {
                    staleFiles.append(item)
                }
            }
        }

        let categories = categoryAccumulators.values
            .map(\.metric)
            .sorted {
                if $0.kind.reviewPriority == $1.kind.reviewPriority {
                    return $0.bytes > $1.bytes
                }

                return $0.kind.reviewPriority > $1.kind.reviewPriority
            }

        let folderHotspots = folderAccumulators.values
            .map(\.metric)
            .filter { $0.bytes >= 100_000_000 || $0.fileCount >= 1_000 }
            .sorted {
                let lhsScore = Double($0.bytes) + (Double($0.fileCount) * 120_000)
                let rhsScore = Double($1.bytes) + (Double($1.fileCount) * 120_000)
                return lhsScore > rhsScore
            }
            .prefix(42)
            .map { $0 }

        staleFiles = staleFiles
            .sorted {
                if $0.cleanupScore == $1.cleanupScore {
                    return $0.bytes > $1.bytes
                }

                return $0.cleanupScore > $1.cleanupScore
            }
            .prefix(60)
            .map { $0 }

        return StorageAnalysisMetric(
            categories: categories,
            folderHotspots: folderHotspots,
            staleFiles: staleFiles,
            scannedFileCount: scannedFiles,
            scannedBytes: scannedBytes
        )
    }

    private func storageFolders(for fileURL: URL, root: URL) -> [URL] {
        let parent = fileURL.deletingLastPathComponent()
        let top = topLevelFolder(for: fileURL, root: root)

        if parent.path == top.path {
            return [top]
        }

        return [top, parent]
    }

    private func topLevelFolder(for fileURL: URL, root: URL) -> URL {
        let relativePath = fileURL.path.replacingOccurrences(of: root.path + "/", with: "")
        guard let firstComponent = relativePath.split(separator: "/").first else {
            return root
        }

        return root.appendingPathComponent(String(firstComponent), isDirectory: true)
    }

    private func storageCategory(for fileURL: URL, root: URL) -> StorageCategoryKind {
        let path = fileURL.path

        if path.contains("/node_modules/")
            || path.contains("/.build/")
            || path.contains("/build/")
            || path.contains("/target/")
            || path.contains("/dist/")
            || path.contains("/DerivedData/") {
            return .packageBuilds
        }

        if path.contains("/Library/Caches/") || path.contains("/.cache/") {
            return .caches
        }

        if path.contains("/Library/Logs/") {
            return .logs
        }

        if path.contains("/Library/Developer/") {
            return .developer
        }

        if path.contains("/Library/Application Support/") {
            return .appSupport
        }

        if path.contains("/Library/Containers/") || path.contains("/Library/Group Containers/") {
            return .containers
        }

        switch root.lastPathComponent {
        case "Downloads":
            return .downloads
        case "Documents", "Desktop":
            return .documents
        case "Movies", "Pictures", "Music":
            return .media
        default:
            return .other
        }
    }

    private func isReviewCandidate(item: StorageItemMetric, kind: StorageCategoryKind) -> Bool {
        let idleDays = item.idleDays ?? 0

        if kind.reviewPriority > 0, item.bytes >= 60_000_000 {
            return true
        }

        if item.bytes >= 1_000_000_000 {
            return true
        }

        if item.bytes >= 50_000_000, idleDays >= 30 {
            return true
        }

        return false
    }

    private func sampleStorageCandidates() -> [StorageItemMetric] {
        let keys: [URLResourceKey] = [
            .isRegularFileKey,
            .fileSizeKey,
            .contentAccessDateKey,
            .contentModificationDateKey
        ]
        var candidates: [StorageItemMetric] = []
        let roots = storageScanRoots()

        for root in roots {
            var scanned = 0
            let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) { _, _ in
                true
            }

            while let fileURL = enumerator?.nextObject() as? URL {
                scanned += 1

                if scanned > 3_500 {
                    break
                }

                guard
                    let values = try? fileURL.resourceValues(forKeys: Set(keys)),
                    values.isRegularFile == true
                else {
                    continue
                }

                let bytes = UInt64(max(values.fileSize ?? 0, 0))
                guard bytes >= 75_000_000 else {
                    continue
                }

                let item = StorageItemMetric(
                    id: fileURL.path,
                    path: fileURL.path,
                    name: fileURL.lastPathComponent,
                    folderName: friendlyFolderName(root),
                    bytes: bytes,
                    lastAccessedAt: values.contentAccessDate,
                    modifiedAt: values.contentModificationDate
                )

                if (item.idleDays ?? 0) >= 7 || bytes >= 500_000_000 {
                    candidates.append(item)
                }
            }
        }

        return candidates
            .sorted {
                if $0.cleanupScore == $1.cleanupScore {
                    return $0.bytes > $1.bytes
                }

                return $0.cleanupScore > $1.cleanupScore
            }
            .prefix(30)
            .map { $0 }
    }

    private func sampleNetworkConnections() -> [NetworkConnectionMetric] {
        guard let output = runCommand("/usr/sbin/lsof", arguments: ["-nP", "-iTCP", "-sTCP:ESTABLISHED"]) else {
            return []
        }

        return output
            .split(separator: "\n")
            .dropFirst()
            .compactMap(parseConnectionLine)
            .prefix(200)
            .map { $0 }
    }

    private func sampleNetworkTrafficByPID() -> [Int: ProcessNetworkTraffic] {
        guard let output = runCommand(
            "/usr/bin/nettop",
            arguments: ["-P", "-x", "-d", "-s", "1", "-L", "2", "-J", "bytes_in,bytes_out"]
        ) else {
            return [:]
        }

        var samples: [[Int: NetworkByteSample]] = []
        var currentSample: [Int: NetworkByteSample] = [:]

        for line in output.split(separator: "\n") {
            if line.hasPrefix(",bytes_in") {
                if !currentSample.isEmpty {
                    samples.append(currentSample)
                    currentSample = [:]
                }

                continue
            }

            guard let traffic = parseNetworkTrafficLine(line) else {
                continue
            }

            currentSample[traffic.pid, default: .zero].add(traffic.value)
        }

        if !currentSample.isEmpty {
            samples.append(currentSample)
        }

        guard !samples.isEmpty else {
            return [:]
        }

        let totalSample = samples.first ?? [:]
        let liveSample = samples.count > 1 ? samples.last ?? [:] : [:]
        let allPIDs = Set(totalSample.keys).union(liveSample.keys)

        return Dictionary(uniqueKeysWithValues: allPIDs.map { pid in
            let total = totalSample[pid] ?? .zero
            let live = liveSample[pid] ?? .zero

            return (
                pid,
                ProcessNetworkTraffic(
                    downloadBytesPerSecond: live.downloadBytes,
                    uploadBytesPerSecond: live.uploadBytes,
                    totalDownloadBytes: total.downloadBytes,
                    totalUploadBytes: total.uploadBytes
                )
            )
        })
    }

    private func sampleAccessCountsByPID() -> [Int: ProcessAccessCounts] {
        guard let output = runCommand("/usr/sbin/lsof", arguments: ["-nP"]) else {
            return [:]
        }

        var counts: [Int: ProcessAccessCounts] = [:]

        for line in output.split(separator: "\n").dropFirst() {
            let parts = line.split(maxSplits: 8, omittingEmptySubsequences: true) { $0 == " " || $0 == "\t" }

            guard parts.count >= 5, let pid = Int(parts[1]) else {
                continue
            }

            let type = String(parts[4])
            let name = parts.count >= 9 ? String(parts[8]) : ""
            var current = counts[pid, default: .zero]

            if isUserFileAccess(type: type, name: name) {
                current.fileCount += 1
            }

            if isSystemAccess(type: type, name: name) {
                current.systemCount += 1
            }

            counts[pid] = current
        }

        return counts
    }

    private func sampleSensors() -> SensorStatusMetric {
        let processInfo = ProcessInfo.processInfo
        let thermal = processInfo.thermalState

        return SensorStatusMetric(
            thermalState: thermal.label,
            thermalDetail: thermal.detail,
            lowPowerMode: currentLowPowerMode(),
            uptime: processInfo.systemUptime,
            activeCoreCount: processInfo.activeProcessorCount,
            coreCount: processInfo.processorCount,
            osVersion: processInfo.operatingSystemVersionString,
            hostName: Host.current().localizedName ?? "This Mac",
            powerAdapterWatts: cachedPowerAdapterWatts()
        )
    }

    private func readCPUTicks() -> CPUTicks? {
        var cpuInfo: processor_info_array_t?
        var numCPUInfo: mach_msg_type_number_t = 0
        var numCPUs: natural_t = 0

        let result = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &numCPUs,
            &cpuInfo,
            &numCPUInfo
        )

        guard result == KERN_SUCCESS, let cpuInfo else {
            return nil
        }

        defer {
            let byteCount = vm_size_t(numCPUInfo) * vm_size_t(MemoryLayout<integer_t>.stride)
            vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: cpuInfo)), byteCount)
        }

        var user: UInt64 = 0
        var system: UInt64 = 0
        var idle: UInt64 = 0
        var nice: UInt64 = 0

        for cpu in 0..<Int(numCPUs) {
            let base = cpu * Int(CPU_STATE_MAX)
            user += UInt64(cpuInfo[base + Int(CPU_STATE_USER)])
            system += UInt64(cpuInfo[base + Int(CPU_STATE_SYSTEM)])
            idle += UInt64(cpuInfo[base + Int(CPU_STATE_IDLE)])
            nice += UInt64(cpuInfo[base + Int(CPU_STATE_NICE)])
        }

        return CPUTicks(user: user, system: system, idle: idle, nice: nice)
    }

    private func readNetworkCounters() -> NetworkCountersSample {
        var interfaces: UnsafeMutablePointer<ifaddrs>?
        var counters: [String: InterfaceCounter] = [:]

        if getifaddrs(&interfaces) == 0 {
            var cursor = interfaces

            while let interface = cursor {
                defer {
                    cursor = interface.pointee.ifa_next
                }

                guard
                    let address = interface.pointee.ifa_addr,
                    Int32(address.pointee.sa_family) == AF_LINK,
                    let data = interface.pointee.ifa_data
                else {
                    continue
                }

                let name = String(cString: interface.pointee.ifa_name)
                let flags = Int32(interface.pointee.ifa_flags)

                guard name != "lo0", flags & IFF_UP != 0 else {
                    continue
                }

                let interfaceData = data.assumingMemoryBound(to: if_data.self).pointee
                counters[name] = InterfaceCounter(
                    name: name,
                    received: UInt64(interfaceData.ifi_ibytes),
                    sent: UInt64(interfaceData.ifi_obytes),
                    baudrate: UInt64(interfaceData.ifi_baudrate)
                )
            }

            freeifaddrs(interfaces)
        }

        return NetworkCountersSample(interfaces: counters, timestamp: Date())
    }

    private func parseProcessLine(_ line: Substring) -> AppUsageMetric? {
        let parts = line.split(maxSplits: 5, omittingEmptySubsequences: true) { $0 == " " || $0 == "\t" }

        guard
            parts.count == 6,
            let pid = Int(parts[0]),
            let parentPID = Int(parts[1]),
            let rssKilobytes = UInt64(parts[3]),
            let cpuPercent = Double(parts[4])
        else {
            return nil
        }

        let ownerName = String(parts[2])
        let commandPath = String(parts[5])
        let name = URL(fileURLWithPath: commandPath).lastPathComponent.nilIfEmpty ?? commandPath

        return AppUsageMetric(
            id: pid,
            pid: pid,
            parentPID: parentPID > 0 ? parentPID : nil,
            name: name,
            commandPath: commandPath,
            ownerName: ownerName,
            residentBytes: rssKilobytes * 1_024,
            cpuPercent: cpuPercent
        )
    }

    private func parseConnectionLine(_ line: Substring) -> NetworkConnectionMetric? {
        let parts = line.split(maxSplits: 8, omittingEmptySubsequences: true) { $0 == " " || $0 == "\t" }

        guard parts.count >= 9, let pid = Int(parts[1]) else {
            return nil
        }

        let endpoint = String(parts[8])
            .replacingOccurrences(of: " (ESTABLISHED)", with: "")
            .replacingOccurrences(of: "(ESTABLISHED)", with: "")
        let sides = endpoint.components(separatedBy: "->")

        guard sides.count == 2 else {
            return nil
        }

        let processName = String(parts[0])
        let local = sides[0]
        let remote = sides[1]

        return NetworkConnectionMetric(
            id: "\(pid)-\(local)-\(remote)",
            processName: processName,
            pid: pid,
            localAddress: local,
            remoteAddress: remote
        )
    }

    private func parseNetworkTrafficLine(_ line: Substring) -> (pid: Int, value: NetworkByteSample)? {
        let parts = line.split(separator: ",", omittingEmptySubsequences: false)

        guard parts.count >= 3 else {
            return nil
        }

        let processAndPID = String(parts[0])

        guard
            let separator = processAndPID.lastIndex(of: "."),
            let pid = Int(processAndPID[processAndPID.index(after: separator)...])
        else {
            return nil
        }

        let downloadBytes = UInt64(String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        let uploadBytes = UInt64(String(parts[2]).trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0

        return (
            pid,
            NetworkByteSample(
                downloadBytes: downloadBytes,
                uploadBytes: uploadBytes
            )
        )
    }

    private func isUserFileAccess(type: String, name: String) -> Bool {
        guard type == "REG" || type == "DIR" else {
            return false
        }

        return name.hasPrefix(NSHomeDirectory() + "/")
    }

    private func isSystemAccess(type: String, name: String) -> Bool {
        if name.hasPrefix("/System/")
            || name.hasPrefix("/Library/")
            || name.hasPrefix("/usr/")
            || name.hasPrefix("/bin/")
            || name.hasPrefix("/sbin/")
            || name.hasPrefix("/private/")
            || name.hasPrefix("/dev/") {
            return true
        }

        return type == "CHR" || type == "KQUEUE" || type == "SYSTEM"
    }

    private func runCommand(_ launchPath: String, arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("disko-\(UUID().uuidString).out")

        FileManager.default.createFile(atPath: outputURL.path, contents: nil)

        guard let outputHandle = try? FileHandle(forWritingTo: outputURL) else {
            return nil
        }

        process.standardOutput = outputHandle
        process.standardError = FileHandle.nullDevice

        defer {
            try? outputHandle.close()
            try? FileManager.default.removeItem(at: outputURL)
        }

        do {
            try process.run()

            let deadline = Date().addingTimeInterval(2.0)
            while process.isRunning, Date() < deadline {
                Thread.sleep(forTimeInterval: 0.03)
            }

            if process.isRunning {
                process.terminate()
                return nil
            }

            try? outputHandle.synchronize()
            let data = try Data(contentsOf: outputURL)
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }

    private func storageScanRoots() -> [URL] {
        let fileManager = FileManager.default
        let home = fileManager.homeDirectoryForCurrentUser
        var roots: [URL] = [
            home.appendingPathComponent("Downloads", isDirectory: true),
            home.appendingPathComponent("Desktop", isDirectory: true),
            home.appendingPathComponent("Documents", isDirectory: true),
            home.appendingPathComponent("Movies", isDirectory: true),
            home.appendingPathComponent("Pictures", isDirectory: true),
            home.appendingPathComponent("Music", isDirectory: true),
            home.appendingPathComponent("Library/Caches", isDirectory: true),
            home.appendingPathComponent("Library/Application Support", isDirectory: true),
            home.appendingPathComponent("Library/Containers", isDirectory: true),
            home.appendingPathComponent("Library/Group Containers", isDirectory: true),
            home.appendingPathComponent("Library/Developer", isDirectory: true),
            home.appendingPathComponent("Library/Logs", isDirectory: true),
            home.appendingPathComponent(".cache", isDirectory: true)
        ]

        roots = roots.filter { fileManager.fileExists(atPath: $0.path) }

        var seen: Set<String> = []
        return roots.filter { seen.insert($0.path).inserted }
    }

    private func friendlyFolderName(_ url: URL) -> String {
        if url.path.hasSuffix("/Library/Caches") {
            return "Caches"
        }

        return url.lastPathComponent.nilIfEmpty ?? url.path
    }

    private func displayName(forInterface name: String) -> String {
        if name.hasPrefix("en") {
            return "Network Link \(name)"
        }

        if name.hasPrefix("utun") {
            return "VPN Tunnel \(name)"
        }

        if name.hasPrefix("awdl") {
            return "Peer Link \(name)"
        }

        if name.hasPrefix("bridge") {
            return "Bridge \(name)"
        }

        if name.hasPrefix("llw") {
            return "Low-Latency Wi-Fi \(name)"
        }

        return name
    }

    private func powerAdapterWatts() -> Int? {
        guard let adapter = IOPSCopyExternalPowerAdapterDetails()?.takeRetainedValue() as? [String: Any] else {
            return nil
        }

        return adapter[kIOPSPowerAdapterWattsKey as String] as? Int
    }

    private func cachedPowerAdapterWatts() -> Int? {
        let now = Date()

        if let cachedPowerAdapterAt, now.timeIntervalSince(cachedPowerAdapterAt) < slowSensorRefreshInterval {
            return cachedAdapterWatts
        }

        cachedAdapterWatts = powerAdapterWatts()
        cachedPowerAdapterAt = now
        return cachedAdapterWatts
    }

    private func cachedSmartBatteryDetails() -> SmartBatteryDetails {
        let now = Date()

        if let cachedSmartBatteryAt, now.timeIntervalSince(cachedSmartBatteryAt) < slowSensorRefreshInterval {
            return cachedBatteryDetails
        }

        cachedBatteryDetails = sampleSmartBatteryDetails()
        cachedSmartBatteryAt = now
        return cachedBatteryDetails
    }

    private func sampleSmartBatteryDetails() -> SmartBatteryDetails {
        var iterator: io_iterator_t = 0
        guard
            let matching = IOServiceMatching("AppleSmartBattery"),
            IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS
        else {
            return .empty
        }

        defer {
            IOObjectRelease(iterator)
        }

        let service = IOIteratorNext(iterator)
        guard service != 0 else {
            return .empty
        }

        defer {
            IOObjectRelease(service)
        }

        let amperage = registryInt("InstantAmperage", service: service) ?? registryInt("Amperage", service: service)
        let voltage = registryInt("Voltage", service: service)
        let watts: Double?

        if let amperage, let voltage, voltage > 0, amperage != 0 {
            watts = abs(Double(amperage) * Double(voltage)) / 1_000_000.0
        } else {
            watts = nil
        }

        return SmartBatteryDetails(
            cycleCount: registryInt("CycleCount", service: service),
            temperatureCelsius: batteryTemperature(from: registryInt("Temperature", service: service)),
            powerWatts: watts
        )
    }

    private func registryInt(_ key: String, service: io_object_t) -> Int? {
        guard let value = IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() else {
            return nil
        }

        return (value as? NSNumber)?.intValue
    }

    private func batteryTemperature(from rawValue: Int?) -> Double? {
        guard let rawValue, rawValue > 0 else {
            return nil
        }

        if rawValue > 1_000 {
            return Double(rawValue) / 100.0
        }

        return Double(rawValue)
    }

    private func currentLowPowerMode() -> Bool {
        if #available(macOS 12.0, *) {
            return ProcessInfo.processInfo.isLowPowerModeEnabled
        }

        return false
    }

    private func positiveMinutes(_ value: Int?) -> Int? {
        guard let value, value >= 0 else { return nil }
        return value
    }

    private func appendHistory(_ history: inout [Double], value: Double, limit: Int) {
        history.append(min(max(value, 0), 1))

        if history.count > limit {
            history.removeFirst(history.count - limit)
        }
    }
}

private struct CPUTicks {
    let user: UInt64
    let system: UInt64
    let idle: UInt64
    let nice: UInt64
}

private struct NetworkCountersSample {
    let interfaces: [String: InterfaceCounter]
    let timestamp: Date
}

private struct InterfaceCounter {
    let name: String
    let received: UInt64
    let sent: UInt64
    let baudrate: UInt64
}

private struct StorageCategoryAccumulator {
    let kind: StorageCategoryKind
    private(set) var bytes: UInt64 = 0
    private(set) var fileCount: Int = 0

    mutating func add(bytes: UInt64) {
        self.bytes += bytes
        fileCount += 1
    }

    var metric: StorageCategoryMetric {
        StorageCategoryMetric(kind: kind, bytes: bytes, fileCount: fileCount)
    }
}

private struct StorageFolderAccumulator {
    let path: String
    let name: String
    let kind: StorageCategoryKind
    private(set) var bytes: UInt64 = 0
    private(set) var fileCount: Int = 0
    private(set) var lastActivity: Date?

    mutating func add(bytes: UInt64, activityDate: Date?) {
        self.bytes += bytes
        fileCount += 1

        if let activityDate, lastActivity.map({ activityDate > $0 }) ?? true {
            lastActivity = activityDate
        }
    }

    var metric: StorageFolderMetric {
        StorageFolderMetric(
            id: path,
            path: path,
            name: name,
            kind: kind,
            bytes: bytes,
            fileCount: fileCount,
            lastActivity: lastActivity
        )
    }
}

extension UInt64 {
    func saturatingDifference(from previous: UInt64) -> UInt64 {
        self >= previous ? self - previous : 0
    }

    var byteString: String {
        ByteFormat.disk(self)
    }

    var shortByteString: String {
        ByteFormat.shortDisk(self)
    }

    var rateString: String {
        "\(ByteFormat.network(self))/s"
    }

    var bitRateString: String {
        ByteFormat.bits(self)
    }
}

extension Double {
    var percentString: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .percent
        formatter.maximumFractionDigits = 0
        formatter.minimumFractionDigits = 0
        return formatter.string(from: NSNumber(value: self)) ?? "\(Int(self * 100))%"
    }

    var wattsString: String {
        let formatter = NumberFormatter()
        formatter.maximumFractionDigits = self >= 10 ? 0 : 1
        formatter.minimumFractionDigits = 0
        return "\(formatter.string(from: NSNumber(value: self)) ?? "\(Int(self))") W"
    }

    var temperatureString: String {
        let formatter = NumberFormatter()
        formatter.maximumFractionDigits = 1
        formatter.minimumFractionDigits = 0
        return "\(formatter.string(from: NSNumber(value: self)) ?? "\(Int(self))") C"
    }
}

extension Int {
    var minutesText: String {
        let hours = self / 60
        let minutes = self % 60

        if hours > 0, minutes > 0 {
            return "\(hours)h \(minutes)m"
        }

        if hours > 0 {
            return "\(hours)h"
        }

        return "\(minutes)m"
    }
}

private extension TimeInterval {
    var uptimeText: String {
        let totalMinutes = Int(self / 60)
        let days = totalMinutes / 1_440
        let hours = (totalMinutes % 1_440) / 60
        let minutes = totalMinutes % 60

        if days > 0 {
            return "\(days)d \(hours)h"
        }

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }

        return "\(minutes)m"
    }
}

private extension Date {
    var relativeAgeText: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: self, relativeTo: Date())
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }

    func deletingSuffix(_ suffix: String) -> String {
        guard hasSuffix(suffix) else {
            return self
        }

        return String(dropLast(suffix.count))
    }
}

private extension ProcessInfo.ThermalState {
    var label: String {
        switch self {
        case .nominal:
            return "Nominal"
        case .fair:
            return "Fair"
        case .serious:
            return "Serious"
        case .critical:
            return "Critical"
        @unknown default:
            return "Unknown"
        }
    }

    var detail: String {
        switch self {
        case .nominal:
            return "Thermals look normal"
        case .fair:
            return "Warm, but still comfortable"
        case .serious:
            return "macOS may reduce performance"
        case .critical:
            return "Thermal pressure is high"
        @unknown default:
            return "macOS reported an unknown thermal state"
        }
    }
}

private enum ByteFormat {
    static func disk(_ bytes: UInt64) -> String {
        makeDiskFormatter().string(fromByteCount: clampedInt64(bytes))
    }

    static func shortDisk(_ bytes: UInt64) -> String {
        makeShortDiskFormatter().string(fromByteCount: clampedInt64(bytes))
    }

    static func network(_ bytes: UInt64) -> String {
        makeNetworkFormatter().string(fromByteCount: clampedInt64(bytes))
    }

    static func bits(_ bitsPerSecond: UInt64) -> String {
        var value = Double(bitsPerSecond)
        let units = ["bps", "Kbps", "Mbps", "Gbps", "Tbps"]
        var unitIndex = 0

        while value >= 1_000, unitIndex < units.count - 1 {
            value /= 1_000
            unitIndex += 1
        }

        let formatter = NumberFormatter()
        formatter.maximumFractionDigits = value >= 10 ? 0 : 1
        formatter.minimumFractionDigits = 0

        return "\(formatter.string(from: NSNumber(value: value)) ?? "\(Int(value))") \(units[unitIndex])"
    }

    private static func clampedInt64(_ bytes: UInt64) -> Int64 {
        Int64(Swift.min(bytes, UInt64(Int64.max)))
    }

    private static func makeDiskFormatter() -> ByteCountFormatter {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB, .useTB]
        formatter.countStyle = .file
        formatter.includesUnit = true
        formatter.isAdaptive = true
        return formatter
    }

    private static func makeShortDiskFormatter() -> ByteCountFormatter {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useTB]
        formatter.countStyle = .file
        formatter.includesUnit = true
        formatter.isAdaptive = true
        formatter.zeroPadsFractionDigits = false
        return formatter
    }

    private static func makeNetworkFormatter() -> ByteCountFormatter {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .binary
        formatter.includesUnit = true
        formatter.isAdaptive = true
        return formatter
    }

}
