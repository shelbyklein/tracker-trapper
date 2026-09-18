import SwiftUI
import TrackerTrapperCore

@main
struct TrackerTrapperMenuBar: App {
    @StateObject private var model = MenuModel()
    var body: some Scene {
        MenuBarExtra { MenuContent(model: model) } label: { Label(model.badge, systemImage: model.symbol) }
            .menuBarExtraStyle(.window)
    }
}

@MainActor final class MenuModel: ObservableObject {
    @Published var snapshot = StoreSnapshot()
    @Published var error: String?
    let store: TrackerStore?
    init() { store = try? TrackerStore(); refresh() }
    var badge: String { let count = snapshot.plans.reduce(0) { $0 + $1.todos.filter { $0.status == .inProgress }.count }; return count == 0 ? "Tracker Trapper" : "\(count)" }
    var symbol: String { snapshot.plans.contains { plan in plan.todos.contains { $0.status == .blocked } } ? "exclamationmark.circle.fill" : "checklist" }
    func refresh() { guard let store else { error = "Unable to open local store"; return }; Task { snapshot = await store.read() } }
}

struct MenuContent: View {
    @ObservedObject var model: MenuModel
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Text("Tracker Trapper").font(.headline); Spacer(); Button("Refresh") { model.refresh() }.keyboardShortcut("r") }
            if let error = model.error { Text(error).foregroundStyle(.red) }
            if model.snapshot.plans.isEmpty { Text("No registered plans yet.").foregroundStyle(.secondary); Text("Use tracker-trapper register-plan to connect an issue.").font(.caption).foregroundStyle(.secondary) }
            ForEach(model.snapshot.plans) { plan in PlanCard(plan: plan, runs: model.snapshot.runs.filter { $0.planID == plan.id }) }
            Divider(); Text("Local updates are saved automatically.").font(.caption).foregroundStyle(.secondary)
        }.padding(16).frame(width: 420)
    }
}

struct PlanCard: View {
    let plan: Plan; let runs: [Run]
    var completed: Int { plan.todos.filter { $0.status == .completed }.count }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack { Text("\(plan.repository) #\(plan.issueNumber)").font(.subheadline.bold()); Spacer(); Text("\(completed)/\(plan.todos.count)").monospacedDigit().foregroundStyle(.secondary) }
            Text(plan.title).lineLimit(2)
            ProgressView(value: Double(completed), total: Double(max(plan.todos.count, 1)))
            ForEach(plan.todos) { todo in HStack(alignment: .top) { Image(systemName: icon(for: todo.status)).foregroundStyle(color(for: todo.status)); Text(todo.description).lineLimit(2) } }
            if let run = runs.sorted(by: { $0.lastActivityAt > $1.lastActivityAt }).first { Text("\(run.agent) · \(run.status.rawValue) · last activity \(run.lastActivityAt.formatted(.relative(presentation: .named)))").font(.caption).foregroundStyle(.secondary) }
        }.padding(10).background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
    }
    func icon(for status: TodoStatus) -> String { switch status { case .completed: "checkmark.circle.fill"; case .inProgress: "circle.inset.filled"; case .blocked: "exclamationmark.triangle.fill"; case .skipped: "minus.circle"; case .pending: "circle" } }
    func color(for status: TodoStatus) -> Color { switch status { case .completed: .green; case .inProgress: .blue; case .blocked: .orange; case .skipped: .secondary; case .pending: .secondary } }
}
