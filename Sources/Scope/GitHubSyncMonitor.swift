import Foundation

@MainActor
final class GitHubSyncMonitor: ObservableObject {
    @Published private(set) var repos: [GitHubRepoStatus] = []
    @Published private(set) var isRefreshing = false
    @Published private(set) var isSyncing = false
    @Published private(set) var lastError: String?
    @Published private(set) var scannedAt: Date?

    private let scanner = RepoScanner(
        githubDir: FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents/GitHub")
    )

    var summary: GitHubSyncSummary { GitHubSyncSummary(repos: repos) }
    var isWorking: Bool { isRefreshing || isSyncing }

    func refresh(fetch: Bool = false) {
        guard !isRefreshing else { return }
        isRefreshing = true
        lastError = nil

        let scanner = self.scanner
        Task.detached(priority: .utility) {
            let discovered = scanner.discoverAll(fetch: fetch)
            await MainActor.run {
                self.repos = discovered
                self.scannedAt = Date()
                self.isRefreshing = false
            }
        }
    }

    func syncAll() {
        guard !isSyncing else { return }
        isSyncing = true
        lastError = nil

        let currentRepos = repos
        let scanner = self.scanner
        Task.detached(priority: .utility) {
            scanner.pullAll(repos: currentRepos)
            await MainActor.run {
                self.isSyncing = false
                self.refresh()
            }
        }
    }
}

// MARK: - Scanner

private struct RepoScanner: Sendable {
    let githubDir: URL

    func discoverAll(fetch: Bool) -> [GitHubRepoStatus] {
        let fm = FileManager.default
        guard let groupURLs = try? fm.contentsOfDirectory(
            at: githubDir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var results: [GitHubRepoStatus] = []

        for groupURL in groupURLs.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            guard isDirectory(groupURL) else { continue }
            let groupName = groupURL.lastPathComponent

            guard let repoURLs = try? fm.contentsOfDirectory(
                at: groupURL,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            for repoURL in repoURLs.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                guard isDirectory(repoURL),
                      fm.fileExists(atPath: repoURL.appendingPathComponent(".git").path)
                else { continue }

                if fetch {
                    git(["fetch", "--all", "--prune"], in: repoURL)
                }

                results.append(scanRepo(group: groupName, at: repoURL))
            }
        }

        return results
    }

    func pullAll(repos: [GitHubRepoStatus]) {
        for repo in repos where !repo.upstream.isEmpty {
            git(["pull", "--ff-only"], in: URL(fileURLWithPath: repo.path))
        }
    }

    private func scanRepo(group: String, at url: URL) -> GitHubRepoStatus {
        let name = url.lastPathComponent
        let remote    = git(["remote", "get-url", "origin"], in: url) ?? ""
        let branch    = git(["rev-parse", "--abbrev-ref", "HEAD"], in: url) ?? ""
        let upstream  = git(["rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{u}"], in: url) ?? ""
        let lastHash  = git(["rev-parse", "--short", "HEAD"], in: url) ?? ""
        let lastMsg   = git(["log", "-1", "--pretty=%s"], in: url) ?? ""
        let porcelain = git(["status", "--porcelain=v1"], in: url) ?? ""

        var ahead = 0, behind = 0
        if !upstream.isEmpty {
            let counts = git(["rev-list", "--left-right", "--count", "HEAD...@{u}"], in: url) ?? "0\t0"
            let parts  = counts.split(separator: "\t", maxSplits: 1).map { Int(String($0)) ?? 0 }
            ahead  = parts.first ?? 0
            behind = parts.last ?? 0
        }

        let lines     = porcelain.isEmpty ? [] : porcelain.components(separatedBy: "\n").filter { !$0.isEmpty }
        let staged    = lines.filter { l in l.count >= 2 && l.first != " " && l.first != "?" }.count
        let unstaged  = lines.filter { l in l.count >= 2 && l[l.index(after: l.startIndex)] != " " && l.first != "?" }.count
        let untracked = lines.filter { $0.hasPrefix("??") }.count
        let clean     = porcelain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        let status: String
        let detail: String
        if !clean {
            (status, detail) = ("dirty", "Local changes are present.")
        } else if upstream.isEmpty {
            (status, detail) = ("no-upstream", "No upstream branch configured.")
        } else if ahead > 0 && behind > 0 {
            (status, detail) = ("diverged", "Local and remote have unique commits.")
        } else if ahead > 0 {
            (status, detail) = ("needs-push", "Local commits to push.")
        } else if behind > 0 {
            (status, detail) = ("needs-pull", "Remote commits to pull.")
        } else {
            (status, detail) = ("synced", "Clean and synced.")
        }

        return GitHubRepoStatus(
            group: group,
            repo: name,
            localFolder: name,
            path: url.path,
            exists: true,
            gitRepo: true,
            clean: clean,
            status: status,
            detail: detail,
            branch: branch,
            upstream: upstream,
            remote: remote,
            ahead: ahead,
            behind: behind,
            staged: staged,
            unstaged: unstaged,
            untracked: untracked,
            lastCommit: lastHash,
            lastSubject: lastMsg,
            error: ""
        )
    }

    @discardableResult
    private func git(_ args: [String], in url: URL) -> String? {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = args
        process.currentDirectoryURL = url
        process.standardOutput = pipe
        process.standardError = Pipe()
        try? process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }
}

// MARK: - Models

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

    var id: String { "\(group)/\(localFolder)" }
    var displayGroup: String { group }

    var statusTitle: String {
        switch status {
        case "synced":      return "Synced"
        case "dirty":       return "Changed"
        case "needs-push":  return "Needs Push"
        case "needs-pull":  return "Needs Pull"
        case "diverged":    return "Diverged"
        case "missing":     return "Missing"
        case "not-git":     return "Not Git"
        case "no-upstream": return "No Upstream"
        case "fetch-error": return "Fetch Error"
        default:            return status
        }
    }

    var needsAttention: Bool { status != "synced" }
    var changeCount: Int { staged + unstaged + untracked }

    var webURL: URL? {
        guard remote.hasPrefix("https://github.com/") else { return nil }
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
        total     = repos.count
        synced    = repos.filter { $0.status == "synced" }.count
        changed   = repos.filter { $0.status == "dirty" }.count
        needsPush = repos.filter { $0.status == "needs-push" }.count
        needsPull = repos.filter { $0.status == "needs-pull" }.count
        missing   = repos.filter { $0.status == "missing" }.count
        issues    = repos.filter { ["diverged", "not-git", "no-upstream", "fetch-error"].contains($0.status) }.count
    }
}
