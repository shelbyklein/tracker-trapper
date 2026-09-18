import Foundation
import TrackerTrapperCore

@main
struct TrackerTrapperMCP {
    static func main() async {
        do { try await serve() }
        catch { fputs("tracker-trapper-mcp: \(error.localizedDescription)\n", stderr); exit(1) }
    }

    static func serve() async throws {
        let store = try TrackerStore()
        while let line = readLine(), let data = line.data(using: .utf8), let request = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
            guard let method = request["method"] as? String else { continue }
            let id = request["id"]
            do {
                let result: Any
                switch method {
                case "initialize": result = ["protocolVersion": "2025-06-18", "capabilities": ["tools": [:]], "serverInfo": ["name": "tracker-trapper", "version": "0.1.0"]]
                case "notifications/initialized": continue
                case "tools/list": result = ["tools": tools]
                case "tools/call": result = try await call(request["params"] as? [String: Any] ?? [:], store: store)
                default: throw MCPError.methodNotFound(method)
                }
                try write(["jsonrpc": "2.0", "id": id ?? NSNull(), "result": result])
            } catch { try write(["jsonrpc": "2.0", "id": id ?? NSNull(), "error": ["code": -32603, "message": error.localizedDescription]]) }
        }
    }

    static var tools: [[String: Any]] {
        [
        tool("register_plan", "Register or update a GitHub issue plan with stable todo IDs", ["repository": "string", "issueNumber": "integer", "issueURL": "string", "title": "string", "todos": "array"]),
        tool("get_plan", "Read a persistent plan and its current progress", ["planID": "string"]),
        tool("start_run", "Associate an agent session with a plan", ["planID": "string", "agent": "string", "sessionID": "string", "repositoryPath": "string"]),
        tool("start_task", "Mark a stable todo as in progress", ["runID": "string", "todoID": "string", "message": "string", "eventID": "string"]),
        tool("complete_task", "Mark a stable todo completed with evidence", ["runID": "string", "todoID": "string", "message": "string", "evidence": "array", "eventID": "string"]),
        tool("update_task", "Set a todo state and attach evidence", ["runID": "string", "todoID": "string", "status": "string", "message": "string", "evidence": "array", "eventID": "string"]),
        tool("report_activity", "Record agent activity without changing task completion", ["runID": "string", "message": "string", "eventID": "string"]),
        tool("finish_run", "Record a paused, interrupted, failed, or finished agent run", ["runID": "string", "status": "string", "message": "string"])
        ]
    }

    static func tool(_ name: String, _ description: String, _ properties: [String: String]) -> [String: Any] {
        ["name": name, "description": description, "inputSchema": ["type": "object", "properties": properties.mapValues { ["type": $0] }]]
    }

    static func call(_ params: [String: Any], store: TrackerStore) async throws -> Any {
        guard let name = params["name"] as? String else { throw MCPError.invalidParams }
        let args = params["arguments"] as? [String: Any] ?? [:]
        switch name {
        case "register_plan":
            let todos = (args["todos"] as? [[String: Any]] ?? []).map { Todo(id: $0["id"] as? String ?? UUID().uuidString, description: $0["description"] as? String ?? "", acceptance: $0["acceptance"] as? String ?? "") }
            let plan = Plan(repository: try string("repository", args), issueNumber: try integer("issueNumber", args), issueURL: try string("issueURL", args), title: try string("title", args), todos: todos)
            return try await store.register(plan).json()
        case "get_plan":
            let id = try string("planID", args); guard let plan = await store.read().plans.first(where: { $0.id == id }) else { throw StoreError.notFound(id) }; return try plan.json()
        case "start_run":
            return try await store.startRun(planID: string("planID", args), agent: string("agent", args), sessionID: string("sessionID", args), repositoryPath: string("repositoryPath", args)).json()
        case "start_task", "complete_task", "update_task":
            let status = name == "start_task" ? TodoStatus.inProgress : name == "complete_task" ? TodoStatus.completed : TodoStatus(rawValue: try string("status", args))
            guard let status else { throw MCPError.invalidParams }
            try await store.update(runID: string("runID", args), todoID: string("todoID", args), status: status, message: args["message"] as? String, evidence: args["evidence"] as? [String] ?? [], eventID: args["eventID"] as? String ?? UUID().uuidString)
            return ["ok": true]
        case "report_activity":
            try await store.update(runID: string("runID", args), todoID: nil, status: nil, message: args["message"] as? String, eventID: args["eventID"] as? String ?? UUID().uuidString); return ["ok": true]
        case "finish_run":
            guard let status = RunStatus(rawValue: try string("status", args)) else { throw MCPError.invalidParams }
            try await store.finishRun(runID: string("runID", args), status: status, message: args["message"] as? String); return ["ok": true]
        default: throw MCPError.methodNotFound(name)
        }
    }

    static func string(_ key: String, _ args: [String: Any]) throws -> String { guard let value = args[key] as? String, !value.isEmpty else { throw MCPError.invalidParams }; return value }
    static func integer(_ key: String, _ args: [String: Any]) throws -> Int { guard let value = args[key] as? Int else { throw MCPError.invalidParams }; return value }
    static func write(_ object: [String: Any]) throws { let data = try JSONSerialization.data(withJSONObject: object); FileHandle.standardOutput.write(data); FileHandle.standardOutput.write("\n".data(using: .utf8)!) }
}

private enum MCPError: Error, LocalizedError { case invalidParams; case methodNotFound(String); var errorDescription: String? { switch self { case .invalidParams: "Invalid params"; case .methodNotFound(let method): "Method not found: \(method)" } } }
private extension Encodable { func json() throws -> Any { try JSONSerialization.jsonObject(with: JSONEncoder().encode(self)) } }
