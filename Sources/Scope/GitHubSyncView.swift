import AppKit
import SwiftUI

struct GitHubSyncView: View {
    @ObservedObject var monitor: GitHubSyncMonitor
    @State private var filter: GitHubSyncFilter = .attention

    private var visibleRepos: [GitHubRepoStatus] {
        switch filter {
        case .attention: return monitor.repos.filter(\.needsAttention)
        case .all:       return monitor.repos
        }
    }

    private var groupedRepos: [(String, [GitHubRepoStatus])] {
        Dictionary(grouping: visibleRepos, by: \.displayGroup)
            .map { ($0.key, $0.value.sorted { $0.localFolder.localizedStandardCompare($1.localFolder) == .orderedAscending }) }
            .sorted { $0.0.localizedStandardCompare($1.0) == .orderedAscending }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            actionBar
            summaryGrid
            filterPicker

            if monitor.repos.isEmpty && monitor.isRefreshing {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 32)
            } else if visibleRepos.isEmpty {
                GitHubEmptyState(
                    icon: "checkmark.circle.fill",
                    title: "All Clear",
                    detail: filter == .attention ? "Every tracked repo is clean and synced." : "No repos match this view."
                )
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(groupedRepos, id: \.0) { group, repos in
                        GitHubRepoGroup(title: group, repos: repos)
                    }
                }
            }

            if let error = monitor.lastError {
                GitHubMessageRow(icon: "exclamationmark.triangle.fill", tint: .orange, title: "Last Error", detail: error)
            }
        }
        .onAppear {
            if monitor.repos.isEmpty {
                monitor.refresh()
            }
        }
    }

    private var actionBar: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("GitHub Sync")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                Text(updatedText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if monitor.isWorking {
                ProgressView()
                    .controlSize(.small)
                    .padding(.trailing, 2)
            }

            Button {
                monitor.refresh()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .disabled(monitor.isWorking)
            .help("Refresh status")

            Button {
                monitor.refresh(fetch: true)
            } label: {
                Label("Fetch", systemImage: "arrow.down.circle")
            }
            .disabled(monitor.isWorking)
            .help("Fetch remotes and refresh status")

            Button {
                monitor.syncAll()
            } label: {
                Label("Sync All", systemImage: "arrow.triangle.2.circlepath")
            }
            .disabled(monitor.isWorking)
            .help("Pull clean repos from GitHub")
        }
    }

    private var summaryGrid: some View {
        let summary = monitor.summary

        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 126), spacing: 10)], spacing: 10) {
            GitHubSummaryCard(title: "Repos", value: "\(summary.total)", icon: "shippingbox", tint: .secondary)
            GitHubSummaryCard(title: "Synced", value: "\(summary.synced)", icon: "checkmark.circle.fill", tint: .green)
            GitHubSummaryCard(title: "Changes", value: "\(summary.changed)", icon: "pencil.circle.fill", tint: .orange)
            GitHubSummaryCard(title: "Push", value: "\(summary.needsPush)", icon: "arrow.up.circle.fill", tint: .blue)
            GitHubSummaryCard(title: "Pull", value: "\(summary.needsPull)", icon: "arrow.down.circle.fill", tint: .indigo)
            GitHubSummaryCard(title: "Issues", value: "\(summary.issues + summary.missing)", icon: "exclamationmark.triangle.fill", tint: .red)
        }
    }

    private var filterPicker: some View {
        Picker("Repo Filter", selection: $filter) {
            ForEach(GitHubSyncFilter.allCases) { item in
                Label(item.title, systemImage: item.icon)
                    .tag(item)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    private var updatedText: String {
        if monitor.isSyncing    { return "Syncing repos..." }
        if monitor.isRefreshing { return "Refreshing status..." }
        guard let scannedAt = monitor.scannedAt else { return "Not scanned yet" }
        return "Updated \(scannedAt.formatted(date: .omitted, time: .standard))"
    }
}

private enum GitHubSyncFilter: String, CaseIterable, Identifiable {
    case attention = "Attention"
    case all = "All"

    var id: String { rawValue }
    var title: String { rawValue }

    var icon: String {
        switch self {
        case .attention: return "exclamationmark.circle"
        case .all:       return "square.grid.2x2"
        }
    }
}

private struct GitHubSummaryCard: View {
    let title: String
    let value: String
    let icon: String
    let tint: Color

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: icon)
                .foregroundStyle(tint)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(value)
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }

            Spacer(minLength: 0)
        }
        .padding(11)
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

private struct GitHubRepoGroup: View {
    let title: String
    let repos: [GitHubRepoStatus]

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Text("\(repos.count)")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            VStack(spacing: 6) {
                ForEach(repos) { repo in
                    GitHubRepoRow(repo: repo)
                }
            }
        }
    }
}

private struct GitHubRepoRow: View {
    let repo: GitHubRepoStatus

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: statusIcon)
                .foregroundStyle(statusTint)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 7) {
                    Text(repo.localFolder)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Text(repo.statusTitle)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(statusTint)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(statusTint.opacity(0.10))
                        )
                }

                Text(detailText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 12)

            HStack(spacing: 10) {
                GitHubRepoMetric(title: "Push", value: repo.ahead, tint: .blue)
                GitHubRepoMetric(title: "Pull", value: repo.behind, tint: .indigo)
                GitHubRepoMetric(title: "Files", value: repo.changeCount, tint: .orange)
            }

            HStack(spacing: 2) {
                Button {
                    reveal()
                } label: {
                    Image(systemName: "folder")
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.borderless)
                .disabled(!repo.exists)
                .help("Reveal folder")

                Button {
                    openRemote()
                } label: {
                    Image(systemName: "arrow.up.right.square")
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.borderless)
                .disabled(repo.webURL == nil)
                .help("Open on GitHub")
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(statusTint.opacity(repo.needsAttention ? 0.42 : 0.18), lineWidth: 1)
        )
        .help(repo.detail)
    }

    private var detailText: String {
        var pieces: [String] = []

        if !repo.branch.isEmpty {
            pieces.append(repo.branch)
        }

        if !repo.lastCommit.isEmpty {
            pieces.append(repo.lastCommit)
        }

        if !repo.lastSubject.isEmpty {
            pieces.append(repo.lastSubject)
        }

        if pieces.isEmpty {
            return repo.detail
        }

        return pieces.joined(separator: " - ")
    }

    private var statusIcon: String {
        switch repo.status {
        case "synced":
            return "checkmark.circle.fill"
        case "dirty":
            return "pencil.circle.fill"
        case "needs-push":
            return "arrow.up.circle.fill"
        case "needs-pull":
            return "arrow.down.circle.fill"
        case "missing":
            return "folder.badge.questionmark"
        case "diverged":
            return "arrow.left.arrow.right.circle.fill"
        default:
            return "exclamationmark.triangle.fill"
        }
    }

    private var statusTint: Color {
        switch repo.status {
        case "synced":
            return .green
        case "dirty":
            return .orange
        case "needs-push":
            return .blue
        case "needs-pull":
            return .indigo
        case "missing", "diverged", "fetch-error":
            return .red
        default:
            return .yellow
        }
    }

    private func reveal() {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: repo.path)])
    }

    private func openRemote() {
        guard let url = repo.webURL else { return }
        NSWorkspace.shared.open(url)
    }
}

private struct GitHubRepoMetric: View {
    let title: String
    let value: Int
    let tint: Color

    var body: some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(title)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.secondary)
            Text("\(value)")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(value == 0 ? .secondary : tint)
                .monospacedDigit()
        }
        .frame(width: 42, alignment: .trailing)
    }
}

private struct GitHubMessageRow: View {
    let icon: String
    let tint: Color
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(tint)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }

            Spacer(minLength: 0)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(tint.opacity(0.08))
        )
    }
}

private struct GitHubEmptyState: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(.green)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }
}
