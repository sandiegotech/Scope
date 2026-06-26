import Foundation
import AppKit
import SwiftUI

@MainActor
final class SystemMonitor: ObservableObject {
    @Published private(set) var snapshot = SystemSnapshot.placeholder
    @Published private(set) var isScanningDetails = false
    @Published private(set) var appHistories: [String: AppUsageHistory] = [:]
    @Published private(set) var batterySessions: [BatterySession] = []
    @Published private(set) var activeSession: BatterySession?

    private let sampler = MetricsSampler()
    private var deepMetrics = DeepMetrics.empty
    private var timer: Timer?
    private var liveScanTimer: Timer?
    private var isScanningLive = false
    private var liveScanCount = 0
    private var sessionDrainerAccumulator: [String: Double] = [:]
    private var lastBatteryWasPluggedIn: Bool? = nil
    private let sessionsKey = "scope_battery_sessions_v1"

    init() {
        deepMetrics = .visibleFallback(from: runningAppProfiles())
        recordAppHistory(from: deepMetrics.topApps)
        batterySessions = loadBatterySessions()

        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }

        liveScanTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshLiveDetails()
            }
        }

        // Defer first load so the placeholder UI renders immediately on launch
        Task { @MainActor [weak self] in
            self?.refresh()
            self?.refreshLiveDetails(includeExpensiveMetrics: false)
        }
    }

    func refresh(forceDeep: Bool = false) {
        snapshot = sampler.capture(deepMetrics: deepMetrics)
        trackBatterySessionTransition()

        if forceDeep {
            refreshDetails()
        }
    }

    func refreshDetails() {
        guard !isScanningDetails else { return }
        isScanningDetails = true
        let appProfiles = runningAppProfiles()
        let existingStorageByPath = deepMetrics.appStorageByPath

        let task = Task.detached(priority: .utility) {
            MetricsSampler().scanDeepMetrics(appProfiles: appProfiles, existingStorageByPath: existingStorageByPath)
        }

        Task { [weak self] in
            let metrics = await task.value

            guard let self else { return }
            deepMetrics = metrics
            recordAppHistory(from: metrics.topApps)
            isScanningDetails = false
            snapshot = sampler.capture(deepMetrics: deepMetrics)
        }
    }

    private func refreshLiveDetails(includeExpensiveMetrics requestedIncludeExpensiveMetrics: Bool? = nil) {
        guard !isScanningDetails, !isScanningLive else { return }
        isScanningLive = true
        liveScanCount += 1
        let existingStorage = deepMetrics.storageCandidates
        let existingStorageAnalysis = deepMetrics.storageAnalysis
        let existingStorageByPath = deepMetrics.appStorageByPath
        let existingApps = deepMetrics.topApps
        let existingConnections = deepMetrics.connections
        let appProfiles = runningAppProfiles()
        let includeExpensiveMetrics = requestedIncludeExpensiveMetrics ?? liveScanCount.isMultiple(of: 4)

        let task = Task.detached(priority: .utility) {
            MetricsSampler().scanLiveMetrics(
                existingStorageCandidates: existingStorage,
                existingStorageAnalysis: existingStorageAnalysis,
                existingStorageByPath: existingStorageByPath,
                existingApps: existingApps,
                existingConnections: existingConnections,
                appProfiles: appProfiles,
                includeExpensiveMetrics: includeExpensiveMetrics
            )
        }

        Task { [weak self] in
            let metrics = await task.value

            guard let self else { return }
            deepMetrics = metrics
            recordAppHistory(from: metrics.topApps)
            isScanningLive = false
            snapshot = sampler.capture(deepMetrics: deepMetrics)
        }
    }

    func resetDownlinkTotal() {
        sampler.resetDownlinkTotal()
        refresh()
    }

    func resetUplinkTotal() {
        sampler.resetUplinkTotal()
        refresh()
    }

    func history(for app: AppUsageMetric) -> AppUsageHistory? {
        appHistories[app.historyKey]
    }

    private func recordAppHistory(from apps: [AppUsageMetric]) {
        let timestamp = Date()
        var histories = appHistories

        for app in apps.prefix(90) {
            if var history = histories[app.historyKey] {
                history.append(app: app, timestamp: timestamp)
                histories[app.historyKey] = history
            } else {
                histories[app.historyKey] = AppUsageHistory(app: app, timestamp: timestamp)
            }
        }

        let cutoff = timestamp.addingTimeInterval(-45 * 60)
        histories = histories.filter { _, history in
            history.latest.map { $0.timestamp >= cutoff } ?? false
        }

        appHistories = histories
        accumulateSessionApps(apps)
    }

    private func runningAppProfiles() -> [RunningAppProfile] {
        NSWorkspace.shared.runningApplications.compactMap { app in
            guard !app.isTerminated, app.processIdentifier > 0 else {
                return nil
            }

            let name = app.localizedName
                ?? app.bundleURL?.deletingPathExtension().lastPathComponent
                ?? app.executableURL?.lastPathComponent
                ?? "Process \(app.processIdentifier)"

            return RunningAppProfile(
                pid: Int(app.processIdentifier),
                name: name,
                bundlePath: app.bundleURL?.path,
                executablePath: app.executableURL?.path,
                isVisible: app.activationPolicy == .regular
            )
        }
    }

    // MARK: - Battery Session Tracking

    private func trackBatterySessionTransition() {
        let battery = snapshot.battery
        guard battery.levelRatio != nil else { return }

        let isPluggedIn = battery.isPluggedIn || battery.isCharging

        if var session = activeSession, let watts = battery.powerWatts {
            if session.peakPowerWatts == nil || watts > (session.peakPowerWatts ?? 0) {
                session.peakPowerWatts = watts
                activeSession = session
            }
        }

        if let previous = lastBatteryWasPluggedIn {
            if previous && !isPluggedIn {
                startBatterySession(battery: battery)
            } else if !previous && isPluggedIn {
                endBatterySession(battery: battery)
            }
        } else if !isPluggedIn, let level = battery.levelRatio, level < 1.0 {
            // App launched while already on battery — start tracking from now
            startBatterySession(battery: battery)
        }

        lastBatteryWasPluggedIn = isPluggedIn
    }

    private func startBatterySession(battery: BatteryMetric) {
        guard let level = battery.levelRatio else { return }
        sessionDrainerAccumulator = [:]
        activeSession = BatterySession(
            id: UUID(),
            startedAt: Date(),
            endedAt: nil,
            startPercent: level,
            endPercent: nil,
            topDrainers: [],
            peakPowerWatts: battery.powerWatts
        )
    }

    private func endBatterySession(battery: BatteryMetric) {
        guard var session = activeSession else { return }
        session.endedAt = Date()
        session.endPercent = battery.levelRatio
        session.topDrainers = topDrainersFromAccumulator()

        var sessions = batterySessions
        sessions.append(session)
        if sessions.count > 10 {
            sessions.removeFirst(sessions.count - 10)
        }
        batterySessions = sessions
        saveBatterySessions(sessions)
        activeSession = nil
        sessionDrainerAccumulator = [:]
    }

    private func accumulateSessionApps(_ apps: [AppUsageMetric]) {
        guard activeSession != nil else { return }
        for app in apps where app.powerImpactScore > 0 {
            sessionDrainerAccumulator[app.name, default: 0] += app.powerImpactScore
        }
    }

    private func topDrainersFromAccumulator() -> [String] {
        Array(
            sessionDrainerAccumulator
                .sorted { $0.value > $1.value }
                .prefix(3)
                .map(\.key)
        )
    }

    private func loadBatterySessions() -> [BatterySession] {
        guard
            let data = UserDefaults.standard.data(forKey: sessionsKey),
            let sessions = try? JSONDecoder().decode([BatterySession].self, from: data)
        else {
            return []
        }
        return sessions
    }

    private func saveBatterySessions(_ sessions: [BatterySession]) {
        guard let data = try? JSONEncoder().encode(sessions) else { return }
        UserDefaults.standard.set(data, forKey: sessionsKey)
    }
}
