import Foundation

public enum SessionFormat: String, Codable, Sendable { case codex, claude }

public struct ObservedCompletion: Equatable, Sendable {
    public let todoID: String
    public let evidence: String
}

public struct SessionObservation: Sendable {
    public let id: String
    public let occurredAt: Date
    public let message: String
    public let completions: [ObservedCompletion]
}

/// Compatibility adapters for local JSONL logs. Never interpret user messages,
/// tool output, reasoning, or tool arguments as completion instructions.
public enum SessionObservationParser {
    public static func identity(_ record: [String: Any], format: SessionFormat) -> String? {
        if format == .codex, record["type"] as? String == "session_meta" {
            return (record["payload"] as? [String: Any])?["id"] as? String
        }
        if format == .claude { return record["sessionId"] as? String }
        return nil
    }

    public static func parse(_ data: Data, format: SessionFormat, sessionID: String, eventID: String, now: Date = .now) throws -> SessionObservation? {
        guard let record = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        guard let stamp = record["timestamp"] as? String, let date = date(stamp), date <= now.addingTimeInterval(60) else { return nil }
        var text: String?
        var activity: String?
        if format == .codex {
            guard record["type"] as? String == "response_item", let item = record["payload"] as? [String: Any] else { return nil }
            switch item["type"] as? String {
            case "message" where item["role"] as? String == "assistant":
                text = (item["content"] as? [[String: Any]] ?? []).filter { $0["type"] as? String == "output_text" }.compactMap { $0["text"] as? String }.joined(separator: "\n")
            case "function_call", "custom_tool_call":
                activity = "Using tool: \(String((item["name"] as? String ?? "tool").prefix(80)))"
            case "function_call_output", "custom_tool_call_output": activity = "Tool returned a result"
            default: return nil
            }
        } else {
            guard record["sessionId"] as? String == sessionID else { return nil }
            let item = record["message"] as? [String: Any] ?? [:]
            let content = item["content"] as? [[String: Any]] ?? []
            if record["type"] as? String == "assistant", item["role"] as? String == "assistant" {
                text = content.filter { $0["type"] as? String == "text" }.compactMap { $0["text"] as? String }.joined(separator: "\n")
                if let tool = content.first(where: { $0["type"] as? String == "tool_use" }) {
                    activity = "Using tool: \(String((tool["name"] as? String ?? "tool").prefix(80)))"
                }
            } else if record["type"] as? String == "user", content.contains(where: { $0["type"] as? String == "tool_result" }) {
                activity = "Tool returned a result"
            } else { return nil }
        }
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty || activity != nil else { return nil }
        let summary = trimmed.isEmpty ? activity! : String(trimmed.replacingOccurrences(of: "\n", with: " ").prefix(240))
        return SessionObservation(id: eventID, occurredAt: date, message: summary, completions: completionMarkers(trimmed))
    }

    public static func completionMarkers(_ text: String) -> [ObservedCompletion] {
        // Full stable IDs, including TT-87-04. Require a standalone assertion
        // with evidence text; ignore quotes, code fences and ordinary prose.
        let expression = try! NSRegularExpression(pattern: #"^(?:- \[[xX]\] |)([A-Za-z][A-Za-z0-9]*(?:-[A-Za-z0-9]+)+)(?:: completed|: done)? [—–-] (.+)$"#)
        var fence: String?
        var result: [ObservedCompletion] = []
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") || line.hasPrefix("~~~") {
                let marker = String(line.prefix(3))
                if fence == nil { fence = marker } else if fence == marker { fence = nil }
                continue
            }
            guard fence == nil, !raw.hasPrefix("    "), !raw.hasPrefix("\t"),
                  line.hasPrefix("- [x] ") || line.hasPrefix("- [X] ") || line.contains(": completed ") || line.contains(": done "),
                  let match = expression.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
                  let idRange = Range(match.range(at: 1), in: line), let evidenceRange = Range(match.range(at: 2), in: line) else { continue }
            result.append(ObservedCompletion(todoID: String(line[idRange]), evidence: String(line[evidenceRange].prefix(300))))
        }
        return result
    }

    private static func date(_ value: String) -> Date? {
        let parser = ISO8601DateFormatter(); parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let result = parser.date(from: value) { return result }
        parser.formatOptions = [.withInternetDateTime]
        return parser.date(from: value)
    }
}
