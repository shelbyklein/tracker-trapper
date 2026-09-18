import Foundation
import TrackerTrapperCore

struct PlanInput: Codable {
    var id: String?
    var repository: String
    var issueNumber: Int
    var issueURL: String
    var title: String
    var todos: [TodoInput]
}
struct TodoInput: Codable { var id: String; var description: String; var acceptance: String? }

@main
struct TrackerTrapperCLI {
    static func main() async {
        do { try await run(Array(CommandLine.arguments.dropFirst())) }
        catch { fputs("tracker-trapper: \(error.localizedDescription)\n", stderr); exit(1) }
    }

    static func run(_ args: [String]) async throws {
        guard let command = args.first else { printHelp(); return }
        let store = try TrackerStore()
        switch command {
        case "--help", "help": printHelp()
        case "register-plan":
            let data = try readInput(args)
            let input = try JSONDecoder().decode(PlanInput.self, from: data)
            let plan = Plan(id: input.id ?? UUID().uuidString, repository: input.repository, issueNumber: input.issueNumber, issueURL: input.issueURL, title: input.title, todos: input.todos.map { Todo(id: $0.id, description: $0.description, acceptance: $0.acceptance ?? "") })
            try printJSON(await store.register(plan))
        case "import-issue":
            guard let repository = value(after: "--repo", in: args), let issue = value(after: "--issue", in: args), let issueNumber = Int(issue) else { throw CLIError.usage("import-issue requires --repo owner/name and --issue number") }
            let imported = try importIssue(repository: repository, issueNumber: issueNumber)
            try printJSON(await store.register(imported))
        case "get-plan":
            guard let id = value(after: "--plan-id", in: args) else { throw CLIError.usage("get-plan requires --plan-id") }
            let result = await store.read().plans.first { $0.id == id || "\($0.issueNumber)" == id }
            guard let result else { throw StoreError.notFound("plan \(id)") }; try printJSON(result)
        case "start-run":
            guard let planID = value(after: "--plan-id", in: args), let agent = value(after: "--agent", in: args), let session = value(after: "--session-id", in: args) else { throw CLIError.usage("start-run requires --plan-id, --agent and --session-id") }
            try printJSON(await store.startRun(planID: planID, agent: agent, sessionID: session, repositoryPath: value(after: "--repo-path", in: args) ?? FileManager.default.currentDirectoryPath))
        case "update-task", "start-task", "complete-task":
            guard let runID = value(after: "--run-id", in: args), let todoID = value(after: "--todo-id", in: args), let raw = value(after: "--status", in: args), let status = TodoStatus(rawValue: raw) else { throw CLIError.usage("update-task requires --run-id, --todo-id and --status") }
            let effectiveStatus = command == "start-task" ? TodoStatus.inProgress : command == "complete-task" ? TodoStatus.completed : status
            try await store.update(runID: runID, todoID: todoID, status: effectiveStatus, message: value(after: "--message", in: args), evidence: values(after: "--evidence", in: args), eventID: value(after: "--event-id", in: args) ?? UUID().uuidString); print("updated")
        case "activity":
            guard let runID = value(after: "--run-id", in: args) else { throw CLIError.usage("activity requires --run-id") }
            try await store.update(runID: runID, todoID: nil, status: nil, message: value(after: "--message", in: args), evidence: values(after: "--evidence", in: args), eventID: value(after: "--event-id", in: args) ?? UUID().uuidString); print("recorded")
        case "record-sync":
            guard let planID = value(after: "--plan-id", in: args), let hash = value(after: "--hash", in: args) else { throw CLIError.usage("record-sync requires --plan-id and --hash") }
            try await store.recordSync(planID: planID, hash: hash); print("recorded")
        case "finish-run":
            guard let runID = value(after: "--run-id", in: args), let raw = value(after: "--status", in: args), let status = RunStatus(rawValue: raw) else { throw CLIError.usage("finish-run requires --run-id and --status") }
            try await store.finishRun(runID: runID, status: status, message: value(after: "--message", in: args)); print("finished")
        case "snapshot": try printJSON(await store.read())
        default: throw CLIError.usage("unknown command \(command)")
        }
    }

    static func readInput(_ args: [String]) throws -> Data { if let path = value(after: "--input", in: args) { return try Data(contentsOf: URL(fileURLWithPath: path)) }; return FileHandle.standardInput.readDataToEndOfFile() }
    static func importIssue(repository: String, issueNumber: Int) throws -> Plan {
        let data = try runProcess("gh", arguments: ["issue", "view", String(issueNumber), "--repo", repository, "--json", "title,body,url"])
        struct Issue: Decodable { let title: String; let body: String; let url: String }
        let issue = try JSONDecoder().decode(Issue.self, from: data)
        let todos = issue.body.split(separator: "\n", omittingEmptySubsequences: false).compactMap { raw -> Todo? in
            let line = String(raw); guard line.hasPrefix("- [") else { return nil }
            guard let markerEnd = line.firstIndex(of: "]"), line.distance(from: line.startIndex, to: markerEnd) >= 3 else { return nil }
            guard let boldStart = line.range(of: "**", range: markerEnd..<line.endIndex), let separator = line.range(of: " — ", range: boldStart.upperBound..<line.endIndex), let boldEnd = line.range(of: "**", range: separator.upperBound..<line.endIndex) else { return nil }
            let id = String(line[boldStart.upperBound..<separator.lowerBound]).trimmingCharacters(in: .whitespaces)
            guard id.hasPrefix("TT-") else { return nil }
            let description = String(line[separator.upperBound..<boldEnd.lowerBound]).trimmingCharacters(in: .whitespaces)
            let suffix = String(line[boldEnd.upperBound...])
            let acceptance = suffix.split(separator: "Check:", maxSplits: 1).dropFirst().first.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? ""
            let checked = line.count > 3 && line[line.index(line.startIndex, offsetBy: 3)] != " "
            return Todo(id: id, description: description, acceptance: acceptance, status: checked ? .completed : .pending)
        }
        return Plan(id: "github:\(repository)#\(issueNumber)", repository: repository, issueNumber: issueNumber, issueURL: issue.url, title: issue.title, todos: todos)
    }
    static func runProcess(_ executable: String, arguments: [String]) throws -> Data {
        let process = Process(); let output = Pipe(); process.executableURL = URL(fileURLWithPath: "/usr/bin/env"); process.arguments = [executable] + arguments; process.standardOutput = output; process.standardError = output
        try process.run(); let data = output.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit(); guard process.terminationStatus == 0 else { throw CLIError.usage(String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)) }; return data
    }
    static func value(after flag: String, in args: [String]) -> String? { guard let index = args.firstIndex(of: flag), args.indices.contains(index + 1) else { return nil }; return args[index + 1] }
    static func values(after flag: String, in args: [String]) -> [String] { args.enumerated().compactMap { $0.element == flag && args.indices.contains($0.offset + 1) ? args[$0.offset + 1] : nil } }
    static func printJSON<T: Encodable>(_ value: T) throws { let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; print(String(decoding: try encoder.encode(value), as: UTF8.self)) }
    static func printHelp() { print("""
    tracker-trapper — local plan/progress bridge
    register-plan --input plan.json
    import-issue --repo owner/name --issue 123
    get-plan --plan-id <id>
    start-run --plan-id <id> --agent <name> --session-id <id> [--repo-path <path>]
    update-task --run-id <id> --todo-id <id> --status <pending|in_progress|blocked|completed|skipped> [--message <text>] [--evidence <value>] [--event-id <id>]
    start-task --run-id <id> --todo-id <id> [--message <text>]
    complete-task --run-id <id> --todo-id <id> [--message <text>] [--evidence <value>]
    activity --run-id <id> [--message <text>] [--event-id <id>]
    finish-run --run-id <id> --status <paused|interrupted|finished|failed|waiting_for_user>
    snapshot
    """) }
}
enum CLIError: Error, LocalizedError { case usage(String); var errorDescription: String? { if case .usage(let text) = self { return text }; return nil } }
