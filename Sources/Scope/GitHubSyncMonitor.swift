import Foundation

@MainActor
final class GitHubSyncMonitor: ObservableObject {
    @Published private(set) var report = GitHubSyncReport.empty
    @Published private(set) var isRefreshing = false
    @Published private(set) var isSyncing = false
    @Published private(set) var lastError: String?
    @Published private(set) var lastOutput = ""

    private let workspaceURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Documents/GitHub")

    var repos: [GitHubRepoStatus] {
        report.repos
    }

    var summary: GitHubSyncSummary {
        GitHubSyncSummary(repos: report.repos)
    }

    var isWorking: Bool {
        isRefreshing || isSyncing
    }

    func refresh(fetch: Bool = false) {
        guard !isRefreshing else { return }

        isRefreshing = true
        lastError = nil

        let scriptURL = workspaceURL.appendingPathComponent(".repo-sync/scripts/status-repos.sh")
        var arguments: [String] = []

        if fetch {
            arguments.append("--fetch")
        }

        Task {
            let result = await ShellRunner.run(scriptURL, arguments: arguments)

            do {
                guard result.exitCode == 0 else {
                    throw GitHubSyncError.commandFailed(result.errorText)
                }

                let decoded = try JSONDecoder().decode(GitHubSyncReport.self, from: Data(result.stdout.utf8))
                report = decoded
                lastOutput = result.combinedOutput
            } catch {
                lastError = error.localizedDescription
                lastOutput = result.combinedOutput
            }

            isRefreshing = false
        }
    }

    func syncAll() {
        guard !isSyncing else { return }

        isSyncing = true
        lastError = nil

        let monolythScript = workspaceURL.appendingPathComponent(".repo-sync/scripts/sync-monolyth-repos.sh")
        let sanDiegoScript = workspaceURL.appendingPathComponent(".repo-sync/scripts/sync-san-diego-tech-repos.sh")

        Task {
            let monolythResult = await ShellRunner.run(monolythScript)
            let sanDiegoResult = await ShellRunner.run(sanDiegoScript)
            let output = [
                monolythResult.combinedOutput,
                sanDiegoResult.combinedOutput
            ]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n")

            if monolythResult.exitCode != 0 || sanDiegoResult.exitCode != 0 {
                lastError = "One or more sync scripts failed."
            }

            lastOutput = output
            isSyncing = false
            refresh()
        }
    }
}

struct GitHubSyncReport: Decodable {
    let workspace: String
    let generatedAt: String
    let repos: [GitHubRepoStatus]

    static let empty = GitHubSyncReport(workspace: "", generatedAt: "", repos: [])
}

struct GitHubRepoStatus: Decodable, Identifiable {
    let group: String
    let repo: String
    let localFolder: String
    let path: String
    let exists: Bool
    let gitRepo: Bool
    let clean: Bool
    let status: String
    let detail: String
    let branch: String
    let upstream: String
    let remote: String
    let ahead: Int
    let behind: Int
    let staged: Int
    let unstaged: Int
    let untracked: Int
    let lastCommit: String
    let lastSubject: String
    let error: String

    var id: String {
        "\(group)/\(localFolder)"
    }

    var displayGroup: String {
        switch group {
        case "monolyth":
            return "Monolyth"
        case "san-diego-tech":
            return "San Diego Tech"
        default:
            return group
        }
    }

    var statusTitle: String {
        switch status {
        case "synced":
            return "Synced"
        case "dirty":
            return "Changed"
        case "needs-push":
            return "Needs Push"
        case "needs-pull":
            return "Needs Pull"
        case "diverged":
            return "Diverged"
        case "missing":
            return "Missing"
        case "not-git":
            return "Not Git"
        case "no-upstream":
            return "No Upstream"
        case "fetch-error":
            return "Fetch Error"
        default:
            return status
        }
    }

    var needsAttention: Bool {
        status != "synced"
    }

    var changeCount: Int {
        staged + unstaged + untracked
    }

    var webURL: URL? {
        guard remote.hasPrefix("https://github.com/") else {
            return nil
        }

        let urlText = remote.hasSuffix(".git") ? String(remote.dropLast(4)) : remote
        return URL(string: urlText)
    }
}

struct GitHubSyncSummary {
    let total: Int
    let synced: Int
    let changed: Int
    let needsPush: Int
    let needsPull: Int
    let missing: Int
    let issues: Int

    init(repos: [GitHubRepoStatus]) {
        total = repos.count
        synced = repos.filter { $0.status == "synced" }.count
        changed = repos.filter { $0.status == "dirty" }.count
        needsPush = repos.filter { $0.status == "needs-push" }.count
        needsPull = repos.filter { $0.status == "needs-pull" }.count
        missing = repos.filter { $0.status == "missing" }.count
        issues = repos.filter { ["diverged", "not-git", "no-upstream", "fetch-error"].contains($0.status) }.count
    }
}

private enum GitHubSyncError: LocalizedError {
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .commandFailed(let output):
            return output.isEmpty ? "GitHub sync command failed." : output
        }
    }
}

private struct ShellResult: Sendable {
    let exitCode: Int32
    let stdout: String
    let stderr: String

    var combinedOutput: String {
        [stdout, stderr]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n")
    }

    var errorText: String {
        stderr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? stdout : stderr
    }
}

private enum ShellRunner {
    static func run(_ executableURL: URL, arguments: [String] = []) async -> ShellResult {
        await Task.detached(priority: .utility) {
            let process = Process()
            let outputPipe = Pipe()
            let errorPipe = Pipe()

            process.executableURL = executableURL
            process.arguments = arguments
            process.standardOutput = outputPipe
            process.standardError = errorPipe

            do {
                try process.run()
                process.waitUntilExit()
            } catch {
                return ShellResult(exitCode: 1, stdout: "", stderr: error.localizedDescription)
            }

            let output = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let error = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

            return ShellResult(exitCode: process.terminationStatus, stdout: output, stderr: error)
        }
        .value
    }
}
