import Foundation

/// Runs an on-demand throughput test against Cloudflare's public speed endpoints.
/// Nothing transfers until `run()` is called, so it never quietly uses data.
@MainActor
final class SpeedTestModel: ObservableObject {
    enum Phase: Equatable {
        case idle
        case downloading
        case uploading
        case done
        case failed
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var downloadMbps: Double?
    @Published private(set) var uploadMbps: Double?
    @Published private(set) var lastRunDate: Date?
    @Published private(set) var errorText: String?

    /// ~25 MiB down, ~10 MiB up per run.
    private let downloadByteCount = 25 * 1024 * 1024
    private let uploadByteCount = 10 * 1024 * 1024

    private let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }()

    var isRunning: Bool {
        phase == .downloading || phase == .uploading
    }

    func run() {
        guard !isRunning else { return }

        errorText = nil
        downloadMbps = nil
        uploadMbps = nil

        Task { await measure() }
    }

    private func measure() async {
        do {
            phase = .downloading
            downloadMbps = try await measureDownload()

            phase = .uploading
            uploadMbps = try await measureUpload()

            lastRunDate = Date()
            phase = .done
        } catch {
            errorText = (error as? SpeedTestError)?.message ?? error.localizedDescription
            phase = .failed
        }
    }

    private func measureDownload() async throws -> Double {
        guard let url = URL(string: "https://speed.cloudflare.com/__down?bytes=\(downloadByteCount)") else {
            throw SpeedTestError.invalidEndpoint
        }

        let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        let start = DispatchTime.now()
        let (data, response) = try await session.data(for: request)
        let seconds = elapsedSeconds(since: start)

        try validate(response)
        return megabitsPerSecond(byteCount: data.count, seconds: seconds)
    }

    private func measureUpload() async throws -> Double {
        guard let url = URL(string: "https://speed.cloudflare.com/__up") else {
            throw SpeedTestError.invalidEndpoint
        }

        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")

        let payload = Data(count: uploadByteCount)
        let start = DispatchTime.now()
        let (_, response) = try await session.upload(for: request, from: payload)
        let seconds = elapsedSeconds(since: start)

        try validate(response)
        return megabitsPerSecond(byteCount: uploadByteCount, seconds: seconds)
    }

    private func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else {
            throw SpeedTestError.badResponse
        }

        guard (200..<300).contains(http.statusCode) else {
            throw SpeedTestError.httpStatus(http.statusCode)
        }
    }

    private func elapsedSeconds(since start: DispatchTime) -> Double {
        Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000_000
    }

    private func megabitsPerSecond(byteCount: Int, seconds: Double) -> Double {
        guard seconds > 0 else { return 0 }
        return Double(byteCount) * 8 / seconds / 1_000_000
    }
}

private enum SpeedTestError: Error {
    case invalidEndpoint
    case badResponse
    case httpStatus(Int)

    var message: String {
        switch self {
        case .invalidEndpoint:
            return "Could not reach the speed test endpoint."
        case .badResponse:
            return "The speed test returned an unexpected response."
        case .httpStatus(let code):
            return "Speed test failed (HTTP \(code))."
        }
    }
}
