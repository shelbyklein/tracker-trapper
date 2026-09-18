import SwiftUI
import AppKit
import Carbon.HIToolbox
import TrackerTrapperCore

@main
struct TrackerTrapperMenuBar: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    var body: some Scene {
        Settings { EmptyView() }
    }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = MenuModel()
    private let popover = NSPopover()
    private var statusItem: NSStatusItem?
    private var hotKey: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem?.button?.image = NSImage(systemSymbolName: "checklist", accessibilityDescription: "Tracker Trapper")
        statusItem?.button?.image?.isTemplate = true
        statusItem?.button?.toolTip = "Tracker Trapper (⌘⇧T)"
        statusItem?.button?.target = self; statusItem?.button?.action = #selector(togglePopover)
        popover.behavior = .transient; popover.animates = true; popover.contentViewController = NSHostingController(rootView: MenuContent(model: model))
        registerHotKey()
    }

    @objc private func togglePopover() {
        guard let button = statusItem?.button else { return }
        if popover.isShown { popover.performClose(nil) } else { model.refresh(); popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY); NSApp.activate(ignoringOtherApps: true) }
    }

    private func registerHotKey() {
        let id = EventHotKeyID(signature: OSType(0x54545250), id: 1)
        RegisterEventHotKey(UInt32(kVK_ANSI_T), UInt32(cmdKey | shiftKey), id, GetApplicationEventTarget(), 0, &hotKey)
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let callback: EventHandlerUPP = { _, _, userData in
            guard let userData else { return noErr }
            let delegate = Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue()
            Task { @MainActor in delegate.togglePopover() }
            return noErr
        }
        InstallEventHandler(GetApplicationEventTarget(), callback, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &eventHandler)
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
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
            Divider(); Text(model.snapshot.outbox.isEmpty ? "Synced or no pending updates." : "\(model.snapshot.outbox.count) update(s) saved locally; GitHub sync pending.").font(.caption).foregroundStyle(.secondary)
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
            if let todo = plan.todos.first(where: { $0.status == .blocked }) { Label("Blocked: \(todo.description)", systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.orange) }
            if let evidence = plan.todos.flatMap(\.evidence).last { Text("Evidence: \(evidence)").font(.caption).lineLimit(2).foregroundStyle(.secondary) }
            if let run = runs.sorted(by: { $0.lastActivityAt > $1.lastActivityAt }).first {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(run.agent) · \(run.status.rawValue)").font(.caption)
                    Text("Activity \(run.lastActivityAt.formatted(.relative(presentation: .named))) · task update \(run.lastTaskUpdateAt?.formatted(.relative(presentation: .named)) ?? "unknown")").font(.caption2).foregroundStyle(.secondary)
                }
            }
            Button("Open GitHub issue") { NSWorkspace.shared.open(URL(string: plan.issueURL)!) }.buttonStyle(.link).font(.caption)
        }.padding(10).background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
    }
    func icon(for status: TodoStatus) -> String { switch status { case .completed: "checkmark.circle.fill"; case .inProgress: "circle.inset.filled"; case .blocked: "exclamationmark.triangle.fill"; case .skipped: "minus.circle"; case .pending: "circle" } }
    func color(for status: TodoStatus) -> Color { switch status { case .completed: .green; case .inProgress: .blue; case .blocked: .orange; case .skipped: .secondary; case .pending: .secondary } }
}
