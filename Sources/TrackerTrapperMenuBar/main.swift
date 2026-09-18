import SwiftUI
import AppKit
import Carbon.HIToolbox
import UserNotifications
import UniformTypeIdentifiers
import TrackerTrapperCore

@main
struct TrackerTrapperMenuBar: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    var body: some Scene {
        Settings { EmptyView() }
    }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate, NSPopoverDelegate {
    private let model = MenuModel()
    private let popover = NSPopover()
    private var statusItem: NSStatusItem?
    private var hotKey: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var refreshTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.model.refresh() }
        }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem?.button?.image = NSImage(systemSymbolName: "checklist", accessibilityDescription: "Tracker Trapper")
        statusItem?.button?.image?.isTemplate = true
        statusItem?.button?.toolTip = "Tracker Trapper (⌘⇧T)"
        statusItem?.button?.target = self; statusItem?.button?.action = #selector(togglePopover)
        popover.behavior = .transient; popover.animates = true; popover.contentViewController = NSHostingController(rootView: MenuContent(model: model, onHeightChange: { [weak self] height in
            guard let self, abs(self.popover.contentSize.height - height) > 0.5 else { return }
            self.popover.contentSize = NSSize(width: 420, height: height)
        }))
        popover.delegate = self
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
            model.maximumPanelHeight = max(200, (screen?.visibleFrame.height ?? 700) - 32)
            popover.contentSize = NSSize(width: 420, height: min(popover.contentSize.height > 0 ? popover.contentSize.height : 200, model.maximumPanelHeight))
            model.refresh()
            model.revealID = UUID()
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

    func popoverDidShow(_ notification: Notification) {
        model.panelDidOpen()
    }

    func popoverDidClose(_ notification: Notification) {
        model.panelDidClose()
    }

    func applicationWillTerminate(_ notification: Notification) {
        refreshTimer?.invalidate()
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard response.actionIdentifier == UNNotificationDefaultActionIdentifier else { return }
        await MainActor.run {
            if !self.popover.isShown { self.togglePopover() }
        }
    }
}

@MainActor final class MenuModel: ObservableObject {
    @Published var maximumPanelHeight: CGFloat = 600
    @Published var revealID = UUID()
    @Published var snapshot = StoreSnapshot()
    @Published private(set) var celebrations = CompletionCelebrations()
    @Published private(set) var celebratingID: String?
    private var celebrationTask: Task<Void, Never>?
    private var panelIsOpen = false
    private var celebrationStateURL: URL?
    @Published private(set) var celebrationError: String?
    private let checksGitHub: Bool
    private let notificationHandler: ((String, String, String) -> Void)?
    @Published var error: String?
    @Published private(set) var attentionItems: [String] = []
    @Published private(set) var watches: [SessionWatch] = []
    @Published private(set) var watcherError: String?
    @Published private(set) var githubError: String?
    private var closedIssueIDs = Set(UserDefaults.standard.stringArray(forKey: "closedGitHubIssueIDs") ?? [])
    private var issueChecksInFlight = false
    private var lastIssueChecks: [String: Date] = [:]
    private var hasLoadedSnapshot = false
    private var dismissedAttentionKeys = Set<String>()
    private var refreshInFlight = false
    private var refreshTask: Task<Void, Never>?
    private var issueCheckTask: Task<Void, Never>?
    private var refreshFeedbackTask: Task<Void, Never>?
    @Published private(set) var isManualRefreshing = false
    @Published private(set) var refreshFeedback: String?
    @Published private(set) var refreshHadError = false
    @Published private(set) var lastManualRefreshAt: Date?
    private let githubStatusCheck: ((Plan) async throws -> Bool)?
    private var dismissedIssueRuns = UserDefaults.standard.dictionary(forKey: "dismissedIssueRuns") as? [String: [String]] ?? [:]
    let store: TrackerStore?
    let watcher: SessionWatcher?
    init(store suppliedStore: TrackerStore? = nil, checksGitHub: Bool = true,
         notificationHandler: ((String, String, String) -> Void)? = nil,
         githubStatusCheck: ((Plan) async throws -> Bool)? = nil) {
        self.githubStatusCheck = githubStatusCheck
        self.checksGitHub = checksGitHub
        self.notificationHandler = notificationHandler
        let opened = suppliedStore ?? (try? TrackerStore())
        store = opened; watcher = opened.map { SessionWatcher(store: $0) }
        celebrationStateURL = opened?.url.deletingPathExtension().appendingPathExtension("celebrations.json")
        if let url = celebrationStateURL, let data = try? Data(contentsOf: url),
           let saved = try? JSONDecoder().decode(CompletionCelebrations.self, from: data) { celebrations = saved }
        refresh()
    }
    var badge: String { let count = snapshot.plans.reduce(0) { $0 + $1.todos.filter { $0.status == .inProgress }.count }; return count == 0 ? "Tracker Trapper" : "\(count)" }
    var symbol: String { snapshot.plans.contains { plan in plan.todos.contains { $0.status == .blocked } } ? "exclamationmark.circle.fill" : "checklist" }
    func refresh() {
        guard let store else { error = "Unable to open local store"; return }
        guard !refreshInFlight else { return }
        refreshInFlight = true
        refreshTask = Task { @MainActor in
            defer { refreshInFlight = false }
            do {
            let source = try await store.read()
            checkGitHubIssues(source.plans)
            if let watcher {
                do {
                    let closedRunIDs = Set(source.runs.filter { closedIssueIDs.contains($0.planID) || celebrations.dismissedPlanIDs.contains($0.planID) }.map(\.id))
                    for watch in try await watcher.reports() where closedRunIDs.contains(watch.runID) {
                        try await watcher.unlink(runID: watch.runID)
                    }
                    watches = try await watcher.poll()
                    let failures = watches.filter { $0.status.hasPrefix("Cannot watch:") }
                    watcherError = failures.isEmpty ? nil : failures.map { watch in
                        let run = source.runs.first { $0.id == watch.runID }
                        let plan = source.plans.first { $0.id == run?.planID }
                        let name = plan.map { "\($0.repository) #\($0.issueNumber)" } ?? "Session"
                        return "\(name): \(watch.status)"
                    }.joined(separator: "\n")
                }
                catch { watcherError = "Session watcher: \(error.localizedDescription)" }
            }
            let current = try await store.read()
            let previousCelebrations = celebrations
            celebrations.observe(visibleSnapshot(current, includingCelebrated: true).plans)
            if celebrations != previousCelebrations { saveCelebrations() }
            if let id = celebratingID, !celebrations.pending.contains(where: { $0.id == id }) { cancelCelebration() }
            let next = visibleSnapshot(current)
            let oldKeys = Set(attentionKeys(for: snapshot))
            let newKeys = Set(attentionKeys(for: next))
            let completions = CompletionNotice.changes(from: hasLoadedSnapshot ? snapshot : nil, to: next)
            snapshot = next
            startCelebrationIfNeeded()
            attentionItems = Array(newKeys.subtracting(dismissedAttentionKeys)).sorted()
            for notice in completions { deliverNotification(title: notice.title, subtitle: notice.subtitle, body: notice.body) }
            if hasLoadedSnapshot {
                // Completion has its own useful message; don't also send a generic alert.
                notify(for: Set(newKeys.subtracting(oldKeys).filter { !$0.hasSuffix(":complete") }))
            }
            hasLoadedSnapshot = true
            error = nil
            } catch { self.error = "Unable to refresh local store: \(error.localizedDescription)" }
        }
    }
    func refreshManually() {
        guard !isManualRefreshing else { return }
        refreshFeedbackTask?.cancel()
        refreshFeedback = nil
        refreshHadError = false
        isManualRefreshing = true
        let before = snapshot.plans
        let beforeWatches = watches
        Task { @MainActor in
            defer { isManualRefreshing = false }
            // Join in-flight work instead of silently dropping the click.
            if let task = refreshTask { await task.value }
            if let task = issueCheckTask { await task.value }
            if let task = refreshTask { await task.value }
            lastIssueChecks.removeAll()
            refresh()
            if let task = refreshTask { await task.value }
            if let task = issueCheckTask { await task.value }
            // Apply the newly checked issue states and unlink closed watchers.
            if let task = refreshTask { await task.value }
            refresh()
            if let task = refreshTask { await task.value }
            lastManualRefreshAt = Date()
            refreshHadError = error != nil || watcherError != nil || githubError != nil || celebrationError != nil
            refreshFeedback = refreshHadError ? "Check notices" : (snapshot.plans == before && watches == beforeWatches ? "Up to date" : "Updated")
            refreshFeedbackTask = Task { @MainActor [weak self] in
                do { try await Task.sleep(for: .seconds(3)) } catch { return }
                self?.refreshFeedback = nil
            }
        }
    }
    private func checkGitHubIssues(_ plans: [Plan]) {
        guard checksGitHub, !issueChecksInFlight else { return }
        let due = plans.filter { Date().timeIntervalSince(lastIssueChecks[$0.id] ?? .distantPast) >= 60 }
        guard !due.isEmpty else { return }
        issueChecksInFlight = true
        issueCheckTask = Task { @MainActor in
            defer { issueChecksInFlight = false }
            var failed = false
            for plan in due {
                lastIssueChecks[plan.id] = Date()
                do {
                    let closed: Bool
                    if let githubStatusCheck {
                        closed = try await githubStatusCheck(plan)
                    } else {
                        let details = try await GitHubIssueStatus.details(plan)
                        closed = details.isClosed
                        if !closed, let title = details.title, let body = details.body, let store {
                            try await store.reconcileGitHubChecklist(planID: plan.id, title: title, todos: GitHubChecklist.parse(body))
                        }
                    }
                    if closed { closedIssueIDs.insert(plan.id) }
                    else { closedIssueIDs.remove(plan.id) }
                    UserDefaults.standard.set(Array(closedIssueIDs), forKey: "closedGitHubIssueIDs")
                    snapshot = visibleSnapshot(snapshot)
                    attentionItems = attentionKeys(for: snapshot).filter { !dismissedAttentionKeys.contains($0) }
                    refresh()
                } catch { failed = true }
            }
            githubError = failed ? "Could not check some GitHub issues. Check gh authentication or network access; saved issue states are retained." : nil
        }
    }
    func linkSession(_ run: Run) {
        let panel = NSOpenPanel(); panel.title = "Link this run's session log"
        panel.message = "Choose the Codex or Claude .jsonl session for this issue. Only new output will be watched."
        panel.allowedContentTypes = [UTType(filenameExtension: "jsonl") ?? .json]; panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url, let watcher else { return }
        Task {
            do {
                _ = try await watcher.link(runID: run.id, sourcePath: url.path, format: run.agent.lowercased().contains("claude") ? .claude : .codex)
                refresh()
            } catch { self.error = "Unable to link session: \(error.localizedDescription)" }
        }
    }
    func unlinkSession(_ planID: String) {
        guard let watcher, let store else { return }
        Task {
            do {
                let current = try await store.read()
                let issueRunIDs = current.runs.filter { $0.planID == planID }.map(\.id)
                for id in issueRunIDs { try await watcher.unlink(runID: id) }
                dismissedIssueRuns[planID] = issueRunIDs
                UserDefaults.standard.set(dismissedIssueRuns, forKey: "dismissedIssueRuns")
                watches.removeAll { issueRunIDs.contains($0.runID) }
                snapshot = visibleSnapshot(current)
                attentionItems.removeAll { item in
                    item.hasPrefix("\(planID):") || issueRunIDs.contains { item.hasPrefix("\($0):") }
                }
                refresh()
            }
            catch { self.error = "Unable to stop watching: \(error.localizedDescription)" }
        }
    }
    private func visibleSnapshot(_ source: StoreSnapshot, includingCelebrated: Bool = false) -> StoreSnapshot {
        // Keep dismissed issues cleared across refreshes and app restarts.
        // A newly started run explicitly resumes tracking the issue.
        let resumedIDs = dismissedIssueRuns.compactMap { planID, knownRuns in
            source.runs.contains { $0.planID == planID && !knownRuns.contains($0.id) } ? planID : nil
        }
        for planID in resumedIDs { dismissedIssueRuns.removeValue(forKey: planID) }
        if !resumedIDs.isEmpty { UserDefaults.standard.set(dismissedIssueRuns, forKey: "dismissedIssueRuns") }
        var visible = source
        if !includingCelebrated {
            visible.plans.removeAll { celebrations.dismissedPlanIDs.contains($0.id) }
            visible.runs.removeAll { celebrations.dismissedPlanIDs.contains($0.planID) }
        }
        visible.plans.removeAll { dismissedIssueRuns[$0.id] != nil || closedIssueIDs.contains($0.id) }
        visible.runs.removeAll { dismissedIssueRuns[$0.planID] != nil || closedIssueIDs.contains($0.planID) }
        return visible
    }
    func panelDidOpen() {
        panelIsOpen = true
        startCelebrationIfNeeded()
    }
    func panelDidClose() {
        panelIsOpen = false
        cancelCelebration()
    }
    private func cancelCelebration() {
        celebrationTask?.cancel()
        celebrationTask = nil
        celebratingID = nil
    }
    private func saveCelebrations() {
        guard let url = celebrationStateURL else { return }
        do {
            try JSONEncoder().encode(celebrations).write(to: url, options: .atomic)
            celebrationError = nil
        } catch { celebrationError = "Unable to save completion celebrations: \(error.localizedDescription)" }
    }
    private func startCelebrationIfNeeded() {
        guard panelIsOpen, celebrationTask == nil,
              let plan = celebrations.pending.first(where: { pending in snapshot.plans.contains { $0.id == pending.id } }) else { return }
        celebratingID = plan.id
        celebrationTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(3)) } catch { return }
            guard let self, !Task.isCancelled, self.panelIsOpen,
                  self.celebratingID == plan.id else { return }
            withAnimation(.easeInOut(duration: 0.5)) {
                self.celebrations.acknowledge(plan.id)
                self.snapshot = self.visibleSnapshot(self.snapshot)
                self.attentionItems = self.attentionKeys(for: self.snapshot).filter { !self.dismissedAttentionKeys.contains($0) }
                self.celebratingID = nil
            }
            self.saveCelebrations()
            do { try await Task.sleep(for: .seconds(0.55)) } catch { return }
            self.celebrationTask = nil
            self.startCelebrationIfNeeded()
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
        deliverNotification(title: "Tracker Trapper", subtitle: "", body: "Agent progress needs your attention.")
    }
    private func deliverNotification(title: String, subtitle: String, body: String) {
        if let notificationHandler { notificationHandler(title, subtitle, body); return }
        let content = UNMutableNotificationContent(); content.title = title; content.subtitle = subtitle; content.body = body; content.sound = .default
        let request = UNNotificationRequest(identifier: "tracker-trapper-\(UUID().uuidString)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}

private struct PanelContentHeight: PreferenceKey {
    static var defaultValue: CGFloat { 0 }
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

private struct ContentSizedScrollView<Content: View>: View {
    let maximumHeight: CGFloat
    let onHeightChange: (CGFloat) -> Void
    var scrollResetToken: String = ""
    @ViewBuilder var content: () -> Content
    @State private var measuredHeight: CGFloat = 200

    var body: some View {
        ScrollViewReader { proxy in
        ScrollView {
            content()
                .id("panel-content-top")
                .fixedSize(horizontal: false, vertical: true)
                .background(GeometryReader { geometry in
                    Color.clear.preference(key: PanelContentHeight.self, value: geometry.size.height)
                })
        }
        .frame(height: min(measuredHeight, maximumHeight))
        .onPreferenceChange(PanelContentHeight.self) { height in
            guard height > 0 else { return }
            measuredHeight = ceil(height)
            onHeightChange(min(ceil(height), maximumHeight))
        }
        .onChange(of: maximumHeight) { limit in onHeightChange(min(measuredHeight, limit)) }
        .onChange(of: scrollResetToken) { _ in proxy.scrollTo("panel-content-top", anchor: .top) }
        }
    }
}

struct MenuContent: View {
    @ObservedObject var model: MenuModel
    var onHeightChange: (CGFloat) -> Void = { _ in }
    @State private var showsNotifications = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var errors: [String] { Array(Set([model.error, model.watcherError, model.githubError, model.celebrationError].compactMap { $0 })).sorted() }
    private var attentionGroups: [(key: String, value: [String])] {
        Dictionary(grouping: model.attentionItems, by: attentionDescription).sorted { $0.key < $1.key }
    }
    private var notificationCount: Int { errors.count + attentionGroups.count }
    private var displayPlans: [Plan] {
        let queued = Set(model.celebrations.pending.map(\.id))
        let order = [model.celebratingID].compactMap { $0 } + model.celebrations.pending.map(\.id).filter { $0 != model.celebratingID }
        return order.compactMap { id in model.snapshot.plans.first { $0.id == id } }
            + model.snapshot.plans.filter { !queued.contains($0.id) }
    }
    var body: some View {
        ContentSizedScrollView(maximumHeight: model.maximumPanelHeight, onHeightChange: onHeightChange,
                               scrollResetToken: "\(model.revealID)-\(model.celebratingID ?? "")") {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Tracker Trapper").font(.headline)
                Spacer()
                Button { showsNotifications.toggle() } label: {
                    HStack(spacing: 4) {
                        Image(systemName: notificationCount == 0 ? "bell" : "bell.badge.fill")
                        if notificationCount > 0 { Text("\(notificationCount)").font(.caption.monospacedDigit()) }
                    }.foregroundStyle(notificationCount == 0 ? Color.secondary : .orange)
                }
                .help(notificationCount == 0 ? "No notifications" : "\(notificationCount) notifications — click to view")
                .accessibilityLabel("Notifications, \(notificationCount)")
                .accessibilityValue(showsNotifications ? "Expanded" : "Collapsed")
                Button { model.refreshManually() } label: {
                    HStack(spacing: 5) {
                        if model.isManualRefreshing {
                            ProgressView().controlSize(.mini)
                            Text("Refreshing…")
                        } else if let feedback = model.refreshFeedback {
                            Image(systemName: model.refreshHadError ? "exclamationmark.circle" : "checkmark")
                            Text(feedback)
                        } else {
                            Text("Refresh")
                        }
                    }
                }
                .keyboardShortcut("r")
                .disabled(model.isManualRefreshing)
                .help(model.lastManualRefreshAt.map { "Last refresh: \($0.formatted(date: .omitted, time: .standard)). Reload progress, read watched sessions, and check GitHub now." } ?? "Reload progress, read watched sessions, and check GitHub now")
            }
            if showsNotifications { notificationDetails }
            VStack(alignment: .leading, spacing: 12) {
                if model.snapshot.plans.isEmpty { Text("No registered plans yet.").foregroundStyle(.secondary); Text("Use tracker-trapper register-plan to connect an issue.").font(.caption).foregroundStyle(.secondary) }
                ForEach(displayPlans) { plan in
                    Group {
                        if model.celebrations.pending.contains(where: { $0.id == plan.id }) {
                            CompletionCelebrationCard(plan: plan, playing: model.celebratingID == plan.id)
                        } else {
                            PlanCard(plan: plan, runs: model.snapshot.runs.filter { $0.planID == plan.id }, watches: model.watches, onLink: model.linkSession, onUnlink: model.unlinkSession)
                        }
                    }
                    .transition(reduceMotion ? .opacity : .asymmetric(insertion: .opacity, removal: .move(edge: .trailing).combined(with: .opacity).combined(with: .scale(scale: 0.92))))
                }
            }.id(model.revealID)
            Divider(); Text(model.snapshot.outbox.isEmpty ? "Synced or no pending updates." : "\(model.snapshot.outbox.count) update(s) saved locally; GitHub sync pending.").font(.caption).foregroundStyle(.secondary)
        }.padding(16).frame(width: 420)
        }.frame(width: 420)
        .onChange(of: model.revealID) { _ in showsNotifications = false }
    }
    private var notificationDetails: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Notifications").font(.subheadline.bold())
                Spacer()
                if !model.attentionItems.isEmpty {
                    Button("Dismiss all") {
                        for item in model.attentionItems { model.dismissAttention(item) }
                    }.font(.caption)
                }
                Button { showsNotifications = false } label: { Image(systemName: "xmark") }
                    .buttonStyle(.borderless).accessibilityLabel("Close notifications")
            }
            if notificationCount == 0 {
                Text("No notifications").font(.caption).foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(errors, id: \.self) { error in
                            Label(error, systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
                        }
                        ForEach(attentionGroups, id: \.key) { group in
                            HStack(alignment: .top) {
                                Label(group.key, systemImage: "bell.fill")
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer()
                                Button("Dismiss") {
                                    for item in group.value { model.dismissAttention(item) }
                                }.buttonStyle(.borderless)
                            }
                        }
                    }.font(.caption).frame(maxWidth: .infinity, alignment: .leading)
                }.frame(maxHeight: 200)
            }
        }.padding(10).background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
    }
    private func attentionDescription(_ key: String) -> String {
        let ownerID = key.split(separator: ":").dropLast().joined(separator: ":")
        let planID = model.snapshot.runs.first { $0.id == ownerID }?.planID ?? ownerID
        if let plan = model.snapshot.plans.first(where: { $0.id == planID }) {
            return "\(plan.repository) #\(plan.issueNumber): \(attentionLabel(key))"
        }
        return attentionLabel(key)
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
    @State private var showsRemainingOnly = true
    let plan: Plan; let runs: [Run]
    let watches: [SessionWatch]
    let onLink: (Run) -> Void
    let onUnlink: (String) -> Void
    var completed: Int { plan.todos.filter { $0.status == .completed }.count }
    var visibleTodos: [Todo] {
        showsRemainingOnly ? plan.todos.filter { $0.status != .completed && $0.status != .skipped } : plan.todos
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Button { showsRemainingOnly.toggle() } label: {
                    HStack {
                        Image(systemName: showsRemainingOnly ? "chevron.right" : "chevron.down")
                        Text("\(plan.repository) #\(plan.issueNumber)").font(.subheadline.bold())
                            .lineLimit(1).truncationMode(.middle)
                    }.contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(showsRemainingOnly ? "Show all tasks" : "Show only remaining tasks")
                .accessibilityValue(showsRemainingOnly ? "Remaining tasks only" : "All tasks")
                Spacer(minLength: 2)
                Text("\(completed)/\(plan.todos.count)").monospacedDigit().foregroundStyle(.secondary)
                if let url = URL(string: plan.issueURL) {
                    Link(destination: url) {
                        GitHubMark().fill(.primary).frame(width: 15, height: 15)
                            .frame(width: 26, height: 26).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 5))
                    .help("Open issue on GitHub")
                    .accessibilityLabel("Open \(plan.repository) #\(plan.issueNumber) on GitHub")
                }
                Group {
                    Button { onUnlink(plan.id) } label: {
                        Image(systemName: "xmark").font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.red).frame(width: 26, height: 26).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 5))
                    .help("Stop watching and remove this issue from Tracker Trapper")
                    .accessibilityLabel("Stop watching \(plan.repository) #\(plan.issueNumber) and remove its task list")
                }
            }
            Text(plan.title).lineLimit(2)
            ProgressView(value: Double(completed), total: Double(max(plan.todos.count, 1)))
            ForEach(runs.filter { run in run.status == .active && !watches.contains { $0.runID == run.id } }) { run in
                HStack {
                    Spacer()
                    Button("Link session…") { onLink(run) }.font(.caption)
                        .accessibilityLabel("Link \(run.agent) session")
                }
            }
            ForEach(visibleTodos) { todo in
                let isNext = plan.nextTodo?.id == todo.id
                HStack(alignment: .top) {
                    Image(systemName: isNext ? "circle.fill" : icon(for: todo.status))
                        .foregroundStyle(isNext ? .blue : color(for: todo.status))
                        .help(isNext ? "Next task" : todo.status.rawValue)
                    Text(todo.description).fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(isNext ? "Next task, " : "")\(todo.status.rawValue): \(todo.description)")
            }
        }.padding(10).background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
    }
    func icon(for status: TodoStatus) -> String { switch status { case .completed: "checkmark.circle.fill"; case .inProgress: "circle.inset.filled"; case .blocked: "exclamationmark.triangle.fill"; case .skipped: "minus.circle"; case .pending: "circle" } }
    func color(for status: TodoStatus) -> Color { switch status { case .completed: .green; case .inProgress: .blue; case .blocked: .orange; case .skipped: .secondary; case .pending: .secondary } }
}

private struct CompletionCelebrationCard: View {
    let plan: Plan
    let playing: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var burst = false

    var body: some View {
        ZStack {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(plan.todos.prefix(5)) { todo in
                    Label(todo.description, systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.secondary).lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(16).blur(radius: 5).opacity(0.45).accessibilityHidden(true)

            if playing && !reduceMotion {
                GeometryReader { geometry in
                    ForEach(0..<30, id: \.self) { index in
                        let angle = Double(index) * 2.39996
                        let distance = Double(65 + (index * 19) % 100)
                        RoundedRectangle(cornerRadius: 2)
                            .fill([Color.yellow, .pink, .cyan, .mint, .purple][index % 5])
                            .frame(width: 5, height: 10)
                            .rotationEffect(.degrees(burst ? Double(index * 47) : 0))
                            .position(x: geometry.size.width / 2 + (burst ? cos(angle) * distance : 0),
                                      y: geometry.size.height / 2 + (burst ? sin(angle) * distance : 0))
                            .opacity(burst ? 0 : 1)
                    }
                }.allowsHitTesting(false).accessibilityHidden(true)
            }

            VStack(spacing: 8) {
                Image(systemName: "party.popper.fill")
                    .font(.system(size: 40)).foregroundStyle(.yellow)
                    .scaleEffect(playing && !reduceMotion ? 1.12 : 1)
                Text("Issue complete!").font(.title2.bold())
                Text("\(plan.repository) #\(plan.issueNumber)").font(.subheadline.bold())
                Text(plan.title).font(.caption).multilineTextAlignment(.center).lineLimit(3)
            }
            .padding(18).frame(maxWidth: .infinity)
        }
        .frame(height: 230)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Issue complete: \(plan.repository) #\(plan.issueNumber), \(plan.title)")
        .task(id: playing) {
            burst = false
            guard playing, !reduceMotion else { return }
            withAnimation(.easeOut(duration: 2.5)) { burst = true }
        }
    }
}

// GitHub mark from Primer Octicons (MIT): https://github.com/primer/octicons
private struct GitHubMark: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 6.766, y: 11.328))
        path.addCurve(to: CGPoint(x: 3.25, y: 7.671999999999999), control1: CGPoint(x: 4.702999999999999, y: 11.078), control2: CGPoint(x: 3.25, y: 9.594))
        path.addCurve(to: CGPoint(x: 4.0, y: 5.483999999999998), control1: CGPoint(x: 3.25, y: 6.890999999999999), control2: CGPoint(x: 3.531, y: 6.046999999999999))
        path.addCurve(to: CGPoint(x: 4.063, y: 3.4219999999999984), control1: CGPoint(x: 3.797, y: 4.9689999999999985), control2: CGPoint(x: 3.828, y: 3.8749999999999982))
        path.addCurve(to: CGPoint(x: 6.031, y: 4.124999999999998), control1: CGPoint(x: 4.688, y: 3.3439999999999985), control2: CGPoint(x: 5.531, y: 3.6719999999999984))
        path.addCurve(to: CGPoint(x: 8.016, y: 3.843999999999998), control1: CGPoint(x: 6.625, y: 3.9379999999999984), control2: CGPoint(x: 7.25, y: 3.843999999999998))
        path.addCurve(to: CGPoint(x: 9.969, y: 4.108999999999998), control1: CGPoint(x: 8.781, y: 3.843999999999998), control2: CGPoint(x: 9.406, y: 3.937999999999998))
        path.addCurve(to: CGPoint(x: 11.937999999999999, y: 3.421999999999998), control1: CGPoint(x: 10.453, y: 3.6719999999999984), control2: CGPoint(x: 11.312999999999999, y: 3.343999999999998))
        path.addCurve(to: CGPoint(x: 11.983999999999998, y: 5.468999999999998), control1: CGPoint(x: 12.155999999999999, y: 3.843999999999998), control2: CGPoint(x: 12.187999999999999, y: 4.936999999999998))
        path.addCurve(to: CGPoint(x: 12.749999999999998, y: 7.671999999999997), control1: CGPoint(x: 12.483999999999998, y: 6.061999999999998), control2: CGPoint(x: 12.749999999999998, y: 6.858999999999997))
        path.addCurve(to: CGPoint(x: 9.202999999999998, y: 11.311999999999998), control1: CGPoint(x: 12.749999999999998, y: 9.593999999999998), control2: CGPoint(x: 11.296999999999999, y: 11.046999999999997))
        path.addCurve(to: CGPoint(x: 10.092999999999998, y: 13.265999999999998), control1: CGPoint(x: 9.733999999999998, y: 11.655999999999997), control2: CGPoint(x: 10.092999999999998, y: 12.405999999999997))
        path.addLine(to: CGPoint(x: 10.092999999999998, y: 14.890999999999998))
        path.addCurve(to: CGPoint(x: 10.952999999999998, y: 15.437999999999999), control1: CGPoint(x: 10.092999999999998, y: 15.358999999999998), control2: CGPoint(x: 10.483999999999998, y: 15.624999999999998))
        path.addCurve(to: CGPoint(x: 16.0, y: 8.03), control1: CGPoint(x: 13.781, y: 14.359), control2: CGPoint(x: 16.0, y: 11.53))
        path.addCurve(to: CGPoint(x: 7.984, y: 0.0), control1: CGPoint(x: 16.0, y: 3.61), control2: CGPoint(x: 12.406, y: 0.0))
        path.addCurve(to: CGPoint(x: 0.0, y: 8.031), control1: CGPoint(x: 3.563, y: 0.0), control2: CGPoint(x: 0.0, y: 3.61))
        path.addCurve(to: CGPoint(x: 5.171999999999999, y: 15.452999999999998), control1: CGPoint(x: -0.009220199158588783, y: 11.346743587366875), control2: CGPoint(x: 2.0581816139718287, y: 14.313537140548227))
        path.addCurve(to: CGPoint(x: 6.0, y: 14.905999999999999), control1: CGPoint(x: 5.593999999999999, y: 15.609), control2: CGPoint(x: 6.0, y: 15.328))
        path.addLine(to: CGPoint(x: 6.0, y: 13.655999999999999))
        path.addCurve(to: CGPoint(x: 5.25, y: 13.812), control1: CGPoint(x: 5.781, y: 13.749999999999998), control2: CGPoint(x: 5.5, y: 13.812))
        path.addCurve(to: CGPoint(x: 3.172, y: 12.203), control1: CGPoint(x: 4.219, y: 13.812), control2: CGPoint(x: 3.6100000000000003, y: 13.25))
        path.addCurve(to: CGPoint(x: 2.4530000000000003, y: 11.484), control1: CGPoint(x: 3.0, y: 11.780999999999999), control2: CGPoint(x: 2.8120000000000003, y: 11.530999999999999))
        path.addCurve(to: CGPoint(x: 2.2030000000000003, y: 11.297), control1: CGPoint(x: 2.2660000000000005, y: 11.469), control2: CGPoint(x: 2.2030000000000003, y: 11.391))
        path.addCurve(to: CGPoint(x: 2.8280000000000003, y: 10.969000000000001), control1: CGPoint(x: 2.2030000000000003, y: 11.109), control2: CGPoint(x: 2.5160000000000005, y: 10.969000000000001))
        path.addCurve(to: CGPoint(x: 4.078, y: 11.829), control1: CGPoint(x: 3.281, y: 10.969000000000001), control2: CGPoint(x: 3.672, y: 11.250000000000002))
        path.addCurve(to: CGPoint(x: 5.109, y: 12.484), control1: CGPoint(x: 4.391, y: 12.281), control2: CGPoint(x: 4.718, y: 12.484))
        path.addCurve(to: CGPoint(x: 6.109, y: 11.984), control1: CGPoint(x: 5.5, y: 12.484), control2: CGPoint(x: 5.75, y: 12.344))
        path.addCurve(to: CGPoint(x: 6.766, y: 11.328), control1: CGPoint(x: 6.375, y: 11.719), control2: CGPoint(x: 6.579, y: 11.484))
        path.closeSubpath()
        return path.applying(CGAffineTransform(scaleX: rect.width / 16, y: rect.height / 16))
    }
}
