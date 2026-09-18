import XCTest
@testable import TrackerTrapperCore

final class GitHubIssueStatusTests: XCTestCase {
    func testOpenClosedAndFailedChecksUseIssueURL() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("issue-status-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let executable = directory.appendingPathComponent("gh")
        let plan = Plan(repository: "test/repo", issueNumber: 1, issueURL: "https://github.example.com/test/repo/issues/1", title: "test", todos: [])
        for (state, expected) in [("OPEN", false), ("CLOSED", true)] {
            try """
            #!/bin/sh
            [ "$1" = issue ] && [ "$2" = view ] && [ "$3" = 'https://github.example.com/test/repo/issues/1' ] && [ "$4" = --json ] && [ "$5" = state,title,body ] || exit 2
            echo '{"state":"\(state)"}'
            """.write(to: executable, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
            let result = try await GitHubIssueStatus.isClosed(plan, executable: executable)
            XCTAssertEqual(result, expected)
        }
        for body in ["exit 1", "echo '{\"state\":\"UNKNOWN\"}'", "echo 'invalid json'"] {
            try "#!/bin/sh\n\(body)\n".write(to: executable, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
            do {
                _ = try await GitHubIssueStatus.isClosed(plan, executable: executable)
                XCTFail("An unsuccessful check must not classify the issue as open or closed")
            } catch {}
        }
    }
}
