import Foundation

public enum GitHubChecklist {
    public static func parse(_ body: String) -> [Todo] {
        let pattern = #"^-\s+\[([ xX])\]\s+\*\*(TT-[A-Za-z0-9-]+)(?:\s+—\s+(.+?)\*\*(.*)|\*\*\s+—\s+(.+))$"#
        let regex = try! NSRegularExpression(pattern: pattern)
        var fenced = false
        var progressBlock = false
        var result: [Todo] = []
        for raw in body.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") || line.hasPrefix("~~~") { fenced.toggle(); continue }
            if line == "<!-- tracker-trapper:progress:start -->" { progressBlock = true; continue }
            if line == "<!-- tracker-trapper:progress:end -->" { progressBlock = false; continue }
            guard !fenced, !progressBlock,
                  let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) else { continue }
            func group(_ index: Int) -> String {
                guard let range = Range(match.range(at: index), in: line) else { return "" }
                return String(line[range]).trimmingCharacters(in: .whitespaces)
            }
            let description = group(3).isEmpty ? group(5) : group(3)
            let acceptance = group(4).components(separatedBy: "Check:").dropFirst().joined(separator: "Check:").trimmingCharacters(in: .whitespaces)
            result.append(Todo(id: group(2), description: description, acceptance: acceptance,
                               status: group(1).lowercased() == "x" ? .completed : .pending))
        }
        return result
    }
}
