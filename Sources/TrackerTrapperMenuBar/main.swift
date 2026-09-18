import SwiftUI
import AppKit
import Carbon.HIToolbox
import UserNotifications
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
        popover.behavior = .applicationDefined; popover.animates = true; popover.contentViewController = NSHostingController(rootView: MenuContent(model: model))
        registerHotKey()
    }

    @objc private func togglePopover() {
        guard let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            // Use the menu-bar display's usable area, excluding the Dock and
            // leaving room for the popover arrow and screen-edge margins.
            let screen = button.window?.screen ?? NSScreen.main
            model.panelHeight = max(200, (screen?.visibleFrame.height ?? 700) - 32)
            popover.contentSize = NSSize(width: 420, height: model.panelHeight)
            model.refresh()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
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
    @Published var panelHeight: CGFloat = 600
    @Published var snapshot = StoreSnapshot()
    @Published var error: String?
    @Published private(set) var attentionItems: [String] = []
    private var hasLoadedSnapshot = false
    private var notificationPermissionRequested = false
    private var dismissedAttentionKeys = Set<String>()
    private var refreshInFlight = false
    let store: TrackerStore?
    init() { store = try? TrackerStore(); refresh() }
    var badge: String { let count = snapshot.plans.reduce(0) { $0 + $1.todos.filter { $0.status == .inProgress }.count }; return count == 0 ? "Tracker Trapper" : "\(count)" }
    var symbol: String { snapshot.plans.contains { plan in plan.todos.contains { $0.status == .blocked } } ? "exclamationmark.circle.fill" : "checklist" }
    func refresh() {
        guard let store else { error = "Unable to open local store"; return }
        guard !refreshInFlight else { return }
        refreshInFlight = true
        Task { @MainActor in
            defer { refreshInFlight = false }
            do {
            let next = try await store.read()
            let oldKeys = Set(attentionKeys(for: snapshot))
            let newKeys = Set(attentionKeys(for: next))
            snapshot = next
            attentionItems = Array(newKeys.subtracting(dismissedAttentionKeys)).sorted()
            if hasLoadedSnapshot { notify(for: newKeys.subtracting(oldKeys)) }
            hasLoadedSnapshot = true
            error = nil
            } catch { self.error = "Unable to refresh local store: \(error.localizedDescription)" }
        }
    }
    func dismissAttention(_ item: String) { dismissedAttentionKeys.insert(item); attentionItems.removeAll { $0 == item } }
    private func attentionKeys(for snapshot: StoreSnapshot) -> [String] {
        let now = Date()
        var result: [String] = []
        for run in snapshot.runs {
            switch run.status {
            case .waitingForUser: result.append("\(run.id):waiting_for_user")
            case .interrupted: result.append("\(run.id):interrupted")
            case .failed: result.append("\(run.id):failed")
            case .active where now.timeIntervalSince(run.lastActivityAt) > 15 * 60: result.append("\(run.id):stale")
            default: break
            }
        }
        for plan in snapshot.plans where !plan.todos.isEmpty && plan.todos.allSatisfy({ $0.status == .completed || $0.status == .skipped }) { result.append("\(plan.id):complete") }
        return result
    }
    private func notify(for keys: Set<String>) {
        let newKeys = keys.subtracting(dismissedAttentionKeys)
        guard !newKeys.isEmpty else { return }
        if notificationPermissionRequested { deliverNotification(); return }
        notificationPermissionRequested = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { [weak self] granted, _ in
            guard granted else { return }
            Task { @MainActor in self?.deliverNotification() }
        }
    }
    private func deliverNotification() {
        let content = UNMutableNotificationContent(); content.title = "Tracker Trapper"; content.body = "Agent progress needs your attention."; content.sound = .default
        let request = UNNotificationRequest(identifier: "tracker-trapper-\(UUID().uuidString)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}

struct MenuContent: View {
    @ObservedObject var model: MenuModel
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Text("Tracker Trapper").font(.headline); Spacer(); Button("Refresh") { model.refresh() }.keyboardShortcut("r") }
            if let error = model.error { Text(error).foregroundStyle(.red) }
            ForEach(model.attentionItems, id: \.self) { item in
                HStack(alignment: .top) {
                    Label(attentionLabel(item), systemImage: "exclamationmark.circle.fill").foregroundStyle(.orange)
                    Spacer()
                    Button("Dismiss") { model.dismissAttention(item) }.buttonStyle(.borderless)
                }.font(.caption).accessibilityElement(children: .combine)
            }
            ScrollView {
                if model.snapshot.plans.isEmpty { Text("No registered plans yet.").foregroundStyle(.secondary); Text("Use tracker-trapper register-plan to connect an issue.").font(.caption).foregroundStyle(.secondary) }
                ForEach(model.snapshot.plans) { plan in PlanCard(plan: plan, runs: model.snapshot.runs.filter { $0.planID == plan.id }) }
            }.frame(maxHeight: .infinity)
            Divider(); Text(model.snapshot.outbox.isEmpty ? "Synced or no pending updates." : "\(model.snapshot.outbox.count) update(s) saved locally; GitHub sync pending.").font(.caption).foregroundStyle(.secondary)
        }.padding(16).frame(width: 420, height: model.panelHeight)
        .task {
            while !Task.isCancelled {
                model.refresh()
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
            }
        }
    }
    func attentionLabel(_ key: String) -> String {
        switch key.split(separator: ":").last.map(String.init) {
        case "waiting_for_user": return "Waiting for your input"
        case "interrupted": return "Agent interrupted"
        case "failed": return "Agent failed"
        case "stale": return "No agent activity for 15 minutes"
        case "complete": return "Plan complete"
        default: return "Agent attention needed"
        }
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
            ForEach(plan.todos) { todo in HStack(alignment: .top) { Image(systemName: icon(for: todo.status)).foregroundStyle(color(for: todo.status)); Text(todo.description).fixedSize(horizontal: false, vertical: true) }.accessibilityElement(children: .ignore).accessibilityLabel("\(todo.status.rawValue): \(todo.description)") }
            if let todo = plan.todos.first(where: { $0.status == .blocked }) { Label("Blocked: \(todo.description)", systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.orange) }
            ForEach(attentionStates, id: \.self) { state in Label(state, systemImage: "bell.badge.fill").font(.caption).foregroundStyle(.orange) }
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
    var attentionStates: [String] {
        runs.compactMap { run in
            switch run.status {
            case .waitingForUser: return "Waiting for your input"
            case .interrupted: return "Agent interrupted"
            case .failed: return "Agent failed"
            case .active where Date().timeIntervalSince(run.lastActivityAt) > 15 * 60: return "Stale: no activity for 15 minutes"
            default: return nil
            }
        }
    }
    func icon(for status: TodoStatus) -> String { switch status { case .completed: "checkmark.circle.fill"; case .inProgress: "circle.inset.filled"; case .blocked: "exclamationmark.triangle.fill"; case .skipped: "minus.circle"; case .pending: "circle" } }
    func color(for status: TodoStatus) -> Color { switch status { case .completed: .green; case .inProgress: .blue; case .blocked: .orange; case .skipped: .secondary; case .pending: .secondary } }
}
