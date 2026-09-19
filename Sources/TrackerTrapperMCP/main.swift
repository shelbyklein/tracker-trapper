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
                case "tools/call":
                    do {
                        let value = try await call(request["params"] as? [String: Any] ?? [:], store: store)
                        let json = try JSONSerialization.data(withJSONObject: value)
                        result = ["content": [["type": "text", "text": String(decoding: json, as: UTF8.self)]], "structuredContent": value, "isError": false]
                    } catch {
                        result = ["content": [["type": "text", "text": error.localizedDescription]], "isError": true]
                    }
                default: throw MCPError.methodNotFound(method)
                }
                try write(["jsonrpc": "2.0", "id": id ?? NSNull(), "result": result])
            } catch { try write(["jsonrpc": "2.0", "id": id ?? NSNull(), "error": ["code": -32603, "message": error.localizedDescription]]) }
        }
    }

    static var tools: [[String: Any]] {
        [
        tool("register_plan", "Register or update a Tracker Trapper-ready GitHub issue plan. Plan directly as one-to-one persistent todos; each todo needs a stable id, one imperative description, and a concrete pass/fail acceptance check", ["repository": "string", "issueNumber": "integer", "issueURL": "string", "title": "string", "todos": "array"]),
        tool("register_local_plan", "Register or retrieve a Tracker Trapper-ready local plan without GitHub. Plan directly as one-to-one persistent todos; each todo needs a stable id, one imperative description, and a concrete pass/fail acceptance check. creationRequestKey makes retries idempotent", ["title": "string", "todos": "array", "workspacePath": "string", "creationRequestKey": "string"]),
        tool("list_local_plans", "List persistent local plans for explicit resumption", [:]),
        tool("get_tracking_settings", "Read whether new interactive sessions should offer local tracking", [:]),
        tool("set_tracking_settings", "Enable or disable the local-tracking question for future sessions", ["askAtSessionStart": "boolean"]),
        tool("get_session_tracking", "Read the tracking decision and binding for one client session", ["client": "string", "sessionID": "string"]),
        tool("set_session_tracking", "Persist a pending, declined or accepted session decision and optional plan/run binding", ["client": "string", "sessionID": "string", "decision": "string", "planID": "string", "runID": "string", "creationRequestKey": "string"]),
        tool("get_plan", "Read a persistent plan and its current progress", ["planID": "string"]),
        tool("start_run", "Associate an agent session with a plan", ["planID": "string", "agent": "string", "sessionID": "string", "repositoryPath": "string"]),
        tool("watch_session", "Link this run to its own local session JSONL file. The menu-bar app watches new output without requiring repeated reporting. format must be codex or claude; sourcePath must be absolute. Historical records are skipped.", ["runID": "string", "sourcePath": "string", "format": "string"]),
        tool("unwatch_session", "Stop observing a linked session without changing its tasks or run", ["runID": "string"]),
        tool("watch_status", "Show linked session watcher status", [:]),
        tool("set_next_task", "Set the issue next task by stable ID; empty nextTodoID clears it", ["runID": "string", "nextTodoID": "string"]),
        tool("start_task", "Mark a stable todo as in progress. Optional nextTodoID selects the next unfinished task; empty string clears it", ["runID": "string", "todoID": "string", "message": "string", "eventID": "string", "nextTodoID": "string"]),
        tool("complete_task", "Mark a stable todo completed with evidence. Optional nextTodoID selects the next unfinished task; empty string clears it", ["runID": "string", "todoID": "string", "message": "string", "evidence": "array", "eventID": "string", "nextTodoID": "string"]),
        tool("update_task", "Set a todo state and attach evidence. Optional nextTodoID selects the next unfinished task; empty string clears it", ["runID": "string", "todoID": "string", "status": "string", "message": "string", "evidence": "array", "eventID": "string", "nextTodoID": "string"]),
        tool("report_activity", "Record agent activity without changing task completion. Optional nextTodoID selects the next unfinished task; empty string clears it", ["runID": "string", "message": "string", "eventID": "string", "nextTodoID": "string"]),
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
        case "register_local_plan":
            let todos = try todoList(args)
            return try await store.registerLocal(title: string("title", args), todos: todos, workspacePath: args["workspacePath"] as? String, creationRequestKey: string("creationRequestKey", args)).json()
        case "list_local_plans":
            return try await store.read().plans.filter { $0.source == .local }.json()
        case "get_tracking_settings":
            return try await store.read().trackingSettings.json()
        case "set_tracking_settings":
            guard let enabled = args["askAtSessionStart"] as? Bool else { throw MCPError.invalidParams }
            return try await store.setTrackingSettings(TrackingSettings(askAtSessionStart: enabled)).json()
        case "get_session_tracking":
            let value = try await store.sessionTracking(client: string("client", args), sessionID: string("sessionID", args))
            var result: [String: Any] = ["session": NSNull()]
            if let value { result["session"] = try value.json() }
            return result
        case "set_session_tracking":
            guard let decision = SessionTrackingDecision(rawValue: try string("decision", args)) else { throw MCPError.invalidParams }
            let value = SessionTracking(client: try string("client", args), sessionID: try string("sessionID", args), decision: decision, planID: args["planID"] as? String, runID: args["runID"] as? String, creationRequestKey: args["creationRequestKey"] as? String)
            return try await store.setSessionTracking(value).json()
        case "get_plan":
            let id = try string("planID", args); guard let plan = try await store.read().plans.first(where: { $0.id == id }) else { throw StoreError.notFound(id) }; return try plan.json()
        case "start_run":
            return try await store.startRun(planID: string("planID", args), agent: string("agent", args), sessionID: string("sessionID", args), repositoryPath: string("repositoryPath", args)).json()
        case "watch_session":
            guard let format = SessionFormat(rawValue: try string("format", args)) else { throw MCPError.invalidParams }
            return try await SessionWatcher(store: store).link(runID: string("runID", args), sourcePath: string("sourcePath", args), format: format).json()
        case "unwatch_session":
            try await SessionWatcher(store: store).unlink(runID: string("runID", args)); return ["ok": true]
        case "watch_status":
            return ["watches": try await SessionWatcher(store: store).reports().json()]
        case "start_task", "complete_task", "update_task":
            let status = name == "start_task" ? TodoStatus.inProgress : name == "complete_task" ? TodoStatus.completed : TodoStatus(rawValue: try string("status", args))
            guard let status else { throw MCPError.invalidParams }
            try await store.update(runID: string("runID", args), todoID: string("todoID", args), status: status, message: args["message"] as? String, evidence: args["evidence"] as? [String] ?? [], eventID: args["eventID"] as? String ?? UUID().uuidString, nextTodoID: args["nextTodoID"] as? String)
            return ["ok": true]
        case "set_next_task":
            guard let nextID = args["nextTodoID"] as? String else { throw MCPError.invalidParams }
            try await store.update(runID: string("runID", args), todoID: nil, status: nil, message: "Next task selection", nextTodoID: nextID)
            return ["ok": true]
        case "report_activity":
            try await store.update(runID: string("runID", args), todoID: nil, status: nil, message: args["message"] as? String, eventID: args["eventID"] as? String ?? UUID().uuidString, nextTodoID: args["nextTodoID"] as? String); return ["ok": true]
        case "finish_run":
            guard let status = RunStatus(rawValue: try string("status", args)) else { throw MCPError.invalidParams }
            try await store.finishRun(runID: string("runID", args), status: status, message: args["message"] as? String); return ["ok": true]
        default: throw MCPError.methodNotFound(name)
        }
    }

    static func string(_ key: String, _ args: [String: Any]) throws -> String { guard let value = args[key] as? String, !value.isEmpty else { throw MCPError.invalidParams }; return value }
    static func integer(_ key: String, _ args: [String: Any]) throws -> Int { guard let value = args[key] as? Int else { throw MCPError.invalidParams }; return value }
    static func todoList(_ args: [String: Any]) throws -> [Todo] {
        guard let raw = args["todos"] as? [[String: Any]], !raw.isEmpty else { throw MCPError.invalidParams }
        return raw.map { Todo(id: $0["id"] as? String ?? "", description: $0["description"] as? String ?? "", acceptance: $0["acceptance"] as? String ?? "") }
    }
    static func write(_ object: [String: Any]) throws { let data = try JSONSerialization.data(withJSONObject: object); FileHandle.standardOutput.write(data); FileHandle.standardOutput.write("\n".data(using: .utf8)!) }
}

private enum MCPError: Error, LocalizedError { case invalidParams; case methodNotFound(String); var errorDescription: String? { switch self { case .invalidParams: "Invalid params"; case .methodNotFound(let method): "Method not found: \(method)" } } }
private extension Encodable { func json() throws -> Any { try JSONSerialization.jsonObject(with: JSONEncoder().encode(self)) } }
