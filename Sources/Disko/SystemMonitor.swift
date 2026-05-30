import Foundation
import AppKit
import SwiftUI

@MainActor
final class SystemMonitor: ObservableObject {
    @Published private(set) var snapshot = SystemSnapshot.placeholder
    @Published private(set) var isScanningDetails = false
    @Published private(set) var appHistories: [String: AppUsageHistory] = [:]

    private let sampler = MetricsSampler()
    private var deepMetrics = DeepMetrics.empty
    private var timer: Timer?
    private var liveScanTimer: Timer?
    private var isScanningLive = false
    private var liveScanCount = 0

    init() {
        deepMetrics = .visibleFallback(from: runningAppProfiles())
        recordAppHistory(from: deepMetrics.topApps)
        refresh()
        refreshLiveDetails(includeExpensiveMetrics: false)

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
    }

    func refresh(forceDeep: Bool = false) {
        snapshot = sampler.capture(deepMetrics: deepMetrics)

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
}
