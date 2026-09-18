import Foundation
import Darwin

public struct GitHubIssueDetails: Sendable {
    public let isClosed: Bool
    public let title: String?
    public let body: String?
}

public enum GitHubIssueStatus {
    /// gh supplies its own authentication; no credentials enter the tracker store.
    public static func isClosed(_ plan: Plan, executable: URL? = nil) async throws -> Bool {
        try await details(plan, executable: executable).isClosed
    }

    public static func details(_ plan: Plan, executable: URL? = nil) async throws -> GitHubIssueDetails {
        try await Task.detached(priority: .utility) { try query(plan, executable: executable) }.value
    }

    private static func query(_ plan: Plan, executable: URL?) throws -> GitHubIssueDetails {
            let process = Process()
            let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent("tracker-github-\(UUID().uuidString).json")
            FileManager.default.createFile(atPath: outputURL.path, contents: nil, attributes: [.posixPermissions: 0o600])
            let output = try FileHandle(forWritingTo: outputURL)
            defer { try? output.close(); try? FileManager.default.removeItem(at: outputURL) }
            let finished = DispatchSemaphore(value: 0)
            let paths = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
                + ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"]
            let resolved = executable ?? paths.map { URL(fileURLWithPath: $0).appendingPathComponent("gh") }
                .first { FileManager.default.isExecutableFile(atPath: $0.path) }
            guard let resolved else { throw StoreError.notFound("GitHub CLI (gh); install it and run gh auth login") }
            process.executableURL = resolved
            // Use the issue URL so enterprise hosts are respected as well.
            process.arguments = ["issue", "view", plan.issueURL, "--json", "state,title,body"]
            process.standardOutput = output
            process.standardError = FileHandle.nullDevice
            process.terminationHandler = { _ in finished.signal() }
            try process.run()
            guard finished.wait(timeout: .now() + 20) == .success else {
                process.terminate()
                if finished.wait(timeout: .now() + 2) == .timedOut { kill(process.processIdentifier, SIGKILL) }
                throw StoreError.conflict("GitHub issue status check timed out")
            }
            guard process.terminationStatus == 0 else {
                throw StoreError.conflict("Unable to check GitHub issue status; check gh authentication and network access")
            }
            struct Response: Decodable { let state: String; let title: String?; let body: String? }
            let response = try JSONDecoder().decode(Response.self, from: Data(contentsOf: outputURL))
            guard response.state == "CLOSED" || response.state == "OPEN" else { throw StoreError.conflict("Unknown GitHub issue state") }
            return GitHubIssueDetails(isClosed: response.state == "CLOSED", title: response.title, body: response.body)
    }
}
