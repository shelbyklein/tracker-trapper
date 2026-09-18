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
        Settings { SettingsView(model: appDelegate.model) }
    }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate, NSPopoverDelegate {
    let model = MenuModel()
    private var settingsController: TrackerSettingsWindow?
    private let popover = NSPopover()
    private let celebrationPanel = CompletionPopoutController()
    private var statusItem: NSStatusItem?
    private var hotKey: EventHotKeyRef?
    private var nextHotKeyID: UInt32 = 1
    private var eventHandler: EventHandlerRef?
    private var shortcutObserver: NSObjectProtocol?
    private var refreshTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        UNUserNotificationCenter.current().delegate = self
        Task { await NotificationService.shared.refresh() }
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.model.refresh() }
        }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem?.button?.image = NSImage(systemSymbolName: "checklist", accessibilityDescription: "Tracker Trapper")
        statusItem?.button?.image?.isTemplate = true
        updateShortcutLabel()
        statusItem?.button?.target = self; statusItem?.button?.action = #selector(togglePopover)
        popover.behavior = .transient; popover.animates = true; popover.contentViewController = NSHostingController(rootView: MenuContent(model: model, onSettings: { [weak self] in self?.showSettings() }, onHeightChange: { [weak self] height in
            guard let self, abs(self.popover.contentSize.height - height) > 0.5 else { return }
            self.popover.contentSize = NSSize(width: 420, height: height)
        }))
        popover.delegate = self
        model.celebrationPresenter = { [weak self] plan in
            guard let self, let button = self.statusItem?.button else { return false }
            return self.celebrationPanel.show(plan: plan, isClosedIssue: self.model.celebrations.isClosedIssue(plan.id),
                                             run: self.model.snapshot.runs.filter { $0.planID == plan.id }.max { $0.lastActivityAt < $1.lastActivityAt },
                                             anchoredTo: button) { [weak self] in self?.model.dismissCelebration() }
        }
        model.todoCelebrationPresenter = { [weak self] celebration in
            guard let self, let button = self.statusItem?.button else { return false }
            return self.celebrationPanel.show(todo: celebration, anchoredTo: button) { [weak self] in self?.model.dismissCelebration() }
        }
        model.celebrationDismissal = { [weak self] in self?.celebrationPanel.hide() }
        registerHotKey()
        shortcutObserver = NotificationCenter.default.addObserver(forName: KeyboardShortcutSettings.changed, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.registerHotKey() }
        }
    }

    @objc func showSettings() {
        popover.performClose(nil)
        if settingsController == nil {
            settingsController = TrackerSettingsWindow(
                model: model,
                onTestCheckboxPopup: { [weak self] in self?.showTestPopup(isCheckbox: true) },
                onTestTaskListPopup: { [weak self] in self?.showTestPopup(isCheckbox: false) }
            )
        }
        settingsController?.reveal()
    }

    private func showTestPopup(isCheckbox: Bool) {
        guard let button = statusItem?.button else { return }
        let dismiss: () -> Void = { [weak self] in self?.celebrationPanel.hide() }
        if isCheckbox {
            _ = celebrationPanel.showTestCheckbox(anchoredTo: button, onDismiss: dismiss)
        } else {
            _ = celebrationPanel.showTestTaskList(anchoredTo: button, onDismiss: dismiss)
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        Task { await NotificationService.shared.refresh() }
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
        let shortcut = KeyboardShortcutSettings.shared.shortcut
        nextHotKeyID &+= 1
        let id = EventHotKeyID(signature: OSType(0x54545250), id: nextHotKeyID)
        var replacement: EventHotKeyRef?
        let status = RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers, id, GetApplicationEventTarget(), 0, &replacement)
        if status == noErr, let replacement {
            if let hotKey { UnregisterEventHotKey(hotKey) }
            hotKey = replacement
        }
        KeyboardShortcutSettings.shared.registrationError = status == noErr ? nil : "That shortcut is unavailable. Choose another combination."
        updateShortcutLabel()
        if eventHandler == nil {
            var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            let callback: EventHandlerUPP = { _, _, userData in
                guard let userData else { return noErr }
                let delegate = Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue()
                Task { @MainActor in delegate.togglePopover() }
                return noErr
            }
            InstallEventHandler(GetApplicationEventTarget(), callback, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &eventHandler)
        }
    }

    private func updateShortcutLabel() {
        statusItem?.button?.toolTip = "Tracker Trapper (\(KeyboardShortcutSettings.shared.shortcut.displayName))"
    }

    func popoverDidShow(_ notification: Notification) {
        model.panelDidOpen()
    }

    func popoverDidClose(_ notification: Notification) {
        model.panelDidClose()
    }

    func applicationWillTerminate(_ notification: Notification) {
        refreshTimer?.invalidate()
        celebrationPanel.hide()
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
        if let shortcutObserver { NotificationCenter.default.removeObserver(shortcutObserver) }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        notification.request.content.sound == nil ? [.banner, .list] : [.banner, .list, .sound]
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
    @Published private(set) var celebratingTodoID: String?
    private var celebrationTask: Task<Void, Never>?
    var celebrationPresenter: ((Plan) -> Bool)?
    var todoCelebrationPresenter: ((TodoCompletionCelebration) -> Bool)?
    var celebrationDismissal: (() -> Void)?
    private var panelIsOpen = false
    private var celebrationStateURL: URL?
    @Published private(set) var celebrationError: String?
    private let checksGitHub: Bool
    private let celebrationsEnabled: () -> Bool
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
    private var observedAttentionKeys = Set<String>()
    @Published private(set) var lastRefreshAt: Date?
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
         githubStatusCheck: ((Plan) async throws -> Bool)? = nil,
         celebrationsEnabled: @escaping () -> Bool = { UserDefaults.standard.object(forKey: "celebrations.enabled") as? Bool ?? true }) {
        self.githubStatusCheck = githubStatusCheck
        self.checksGitHub = checksGitHub
        self.celebrationsEnabled = celebrationsEnabled
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
            checkGitHubIssues(source.plans.filter(\.isGitHub))
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
                        let name = plan?.displaySubtitle ?? "Session"
                        return "\(name): \(watch.status)"
                    }.joined(separator: "\n")
                }
                catch { watcherError = "Session watcher: \(error.localizedDescription)" }
            }
            let current = try await store.read()
            let previousCelebrations = celebrations
            celebrations.observe(visibleSnapshot(current, includingCelebrated: true, includingClosed: true).plans)
            if celebrations != previousCelebrations { saveCelebrations() }
            if let id = celebratingID, !celebrations.pending.contains(where: { $0.id == id }) { cancelCelebration() }
            if let id = celebratingTodoID, !celebrations.pendingTodos.contains(where: { $0.id == id }) { cancelCelebration() }
            let next = visibleSnapshot(current)
            let oldKeys = observedAttentionKeys
            let newKeys = Set(attentionKeys(for: next))
            let knownPlans = Set(snapshot.plans.map(\.id))
            let completions = CompletionNotice.changes(from: hasLoadedSnapshot ? snapshot : nil, to: next)
            snapshot = next
            dismissedAttentionKeys.formIntersection(newKeys)
            observedAttentionKeys = newKeys
            attentionItems = Array(newKeys.subtracting(dismissedAttentionKeys)).sorted()
            for notice in completions { deliverNotification(title: notice.title, subtitle: notice.subtitle, body: notice.body, kind: .completion) }
            if hasLoadedSnapshot {
                let notices = AttentionNotice.current(next).filter { knownPlans.contains($0.planID) && !oldKeys.contains($0.id) }
                for notice in notices where !dismissedAttentionKeys.contains(notice.id) {
                    deliverNotification(title: "Tracker Trapper", subtitle: notice.subtitle, body: notice.body, kind: notice.isStale ? .stale : .attention)
                }
            }
            hasLoadedSnapshot = true
            lastRefreshAt = .now
            startCelebrationIfNeeded()
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
        let due = plans.filter { $0.isGitHub && Date().timeIntervalSince(lastIssueChecks[$0.id] ?? .distantPast) >= 60 }
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
                    let previousCelebrations = celebrations
                    if dismissedIssueRuns[plan.id] == nil {
                        celebrations.observeGitHubIssue(plan, isClosed: closed)
                    }
                    if celebrations != previousCelebrations { saveCelebrations() }
                    if let id = celebratingID, !celebrations.pending.contains(where: { $0.id == id }) { cancelCelebration() }
                    if let id = celebratingTodoID, !celebrations.pendingTodos.contains(where: { $0.id == id }) { cancelCelebration() }
                    if closed { closedIssueIDs.insert(plan.id) }
                    else { closedIssueIDs.remove(plan.id) }
                    UserDefaults.standard.set(Array(closedIssueIDs), forKey: "closedGitHubIssueIDs")
                    snapshot = visibleSnapshot(snapshot)
                    attentionItems = attentionKeys(for: snapshot).filter { !dismissedAttentionKeys.contains($0) }
                    startCelebrationIfNeeded()
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
    private func visibleSnapshot(_ source: StoreSnapshot, includingCelebrated: Bool = false, includingClosed: Bool = false) -> StoreSnapshot {
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
        visible.plans.removeAll { dismissedIssueRuns[$0.id] != nil || (!includingClosed && closedIssueIDs.contains($0.id)) }
        visible.runs.removeAll { dismissedIssueRuns[$0.planID] != nil || (!includingClosed && closedIssueIDs.contains($0.planID)) }
        return visible
    }
    func panelDidOpen() {
        panelIsOpen = true
        cancelCelebration()
        startCelebrationIfNeeded()
    }
    func panelDidClose() {
        panelIsOpen = false
        cancelCelebration()
        startCelebrationIfNeeded()
    }
    private func cancelCelebration() {
        celebrationTask?.cancel()
        celebrationTask = nil
        celebratingID = nil
        celebratingTodoID = nil
        celebrationDismissal?()
    }
    private func saveCelebrations() {
        guard let url = celebrationStateURL else { return }
        do {
            try JSONEncoder().encode(celebrations).write(to: url, options: .atomic)
            celebrationError = nil
        } catch { celebrationError = "Unable to save completion celebrations: \(error.localizedDescription)" }
    }
    private func startCelebrationIfNeeded() {
        if !celebrationsEnabled() {
            cancelCelebration()
            let changed = celebrations.acknowledgeWithoutAnimation()
            if changed { snapshot = visibleSnapshot(snapshot); saveCelebrations() }
            return
        }
        guard celebrationTask == nil else { return }
        if let todo = celebrations.pendingTodos.first {
            guard let todoCelebrationPresenter else {
                celebrations.acknowledgeTodo(todo.id)
                saveCelebrations()
                startCelebrationIfNeeded()
                return
            }
            guard todoCelebrationPresenter(todo) else { return }
            celebratingTodoID = todo.id
            celebrationTask = Task { @MainActor [weak self] in
                do { try await Task.sleep(for: .milliseconds(2600)) } catch { return }
                guard let self, !Task.isCancelled,
                      self.celebratingTodoID == todo.id else { return }
                self.acknowledgeTodoCelebration(todo.id)
                do { try await Task.sleep(for: .seconds(0.55)) } catch { return }
                self.celebrationTask = nil
                self.startCelebrationIfNeeded()
            }
            return
        }
        guard let plan = celebrations.pending.first else { return }
        if !panelIsOpen {
            // Do not consume the persisted queue until a window was actually shown.
            guard celebrationPresenter?(plan) == true else { return }
        }
        celebratingID = plan.id
        let duration: Duration = .milliseconds(5000 + plan.todos.count * 550)
        celebrationTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: duration) } catch { return }
            guard let self, !Task.isCancelled,
                  self.celebratingID == plan.id else { return }
            self.acknowledgeCelebration(plan.id)
            do { try await Task.sleep(for: .seconds(0.55)) } catch { return }
            self.celebrationTask = nil
            self.startCelebrationIfNeeded()
        }
    }
    func dismissCelebration() {
        if let id = celebratingTodoID {
            cancelCelebration()
            acknowledgeTodoCelebration(id)
            startCelebrationIfNeeded()
            return
        }
        guard let id = celebratingID else { return }
        cancelCelebration()
        acknowledgeCelebration(id)
        startCelebrationIfNeeded()
    }
    private func acknowledgeTodoCelebration(_ id: String) {
        celebrations.acknowledgeTodo(id)
        celebratingTodoID = nil
        celebrationDismissal?()
        saveCelebrations()
    }
    private func acknowledgeCelebration(_ id: String) {
        withAnimation(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? nil : .easeInOut(duration: 0.5)) {
            celebrations.acknowledge(id)
            snapshot = visibleSnapshot(snapshot)
            attentionItems = attentionKeys(for: snapshot).filter { !dismissedAttentionKeys.contains($0) }
            celebratingID = nil
        }
        celebrationDismissal?()
        saveCelebrations()
    }
    func dismissAttention(_ item: String) { dismissedAttentionKeys.insert(item); attentionItems.removeAll { $0 == item } }
    private func attentionKeys(for snapshot: StoreSnapshot) -> [String] {
        AttentionNotice.current(snapshot).map(\.id)
    }
    private func deliverNotification(title: String, subtitle: String, body: String, kind: NoticeKind) {
        if let notificationHandler { notificationHandler(title, subtitle, body); return }
        Task { await NotificationService.shared.send(title: title, subtitle: subtitle, body: body, kind: kind) }
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
    var onSettings: () -> Void = {}
    var onHeightChange: (CGFloat) -> Void = { _ in }
    @ObservedObject private var notifications = NotificationService.shared
    @AppStorage("setup.dismissed") private var setupDismissed = false
    @State private var showsNotifications = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var errors: [String] { Array(Set([model.error, model.watcherError, model.githubError, model.celebrationError, notifications.lastError].compactMap { $0 })).sorted() }
    private var attentionGroups: [(key: String, value: [String])] {
        Dictionary(grouping: model.attentionItems, by: attentionDescription).sorted { $0.key < $1.key }
    }
    private var notificationCount: Int { errors.count + attentionGroups.count }
    private var displayPlans: [Plan] {
        let queued = Set(model.celebrations.pending.map(\.id))
        let order = [model.celebratingID].compactMap { $0 } + model.celebrations.pending.map(\.id).filter { $0 != model.celebratingID }
        return order.compactMap { id in model.celebrations.pending.first { $0.id == id } }
            + model.snapshot.plans.filter { !queued.contains($0.id) }
    }
    var body: some View {
        ContentSizedScrollView(maximumHeight: model.maximumPanelHeight, onHeightChange: onHeightChange,
                               scrollResetToken: "\(model.revealID)-\(model.celebratingID ?? "")-\(model.celebratingTodoID ?? "")") {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Tracker Trapper").font(.system(size: 17, weight: .bold)).tracking(-0.5)
                Spacer()
                Button(action: onSettings) {
                    Image(systemName: "gearshape")
                        .foregroundStyle(.white)
                }
                .buttonStyle(.borderless)
                .help("Open Tracker Trapper Settings")
                .accessibilityLabel("Open Tracker Trapper Settings")
                Button { showsNotifications.toggle() } label: {
                    HStack(spacing: 4) {
                        Image(systemName: notificationCount == 0 ? "bell" : "bell.badge.fill")
                        if notificationCount > 0 { Text("\(notificationCount)").font(.caption.monospacedDigit()) }
                    }.foregroundStyle(.white)
                }
                .help(notificationCount == 0 ? "No notifications" : "\(notificationCount) notifications — click to view")
                .accessibilityLabel("Notifications, \(notificationCount)")
                .accessibilityValue(showsNotifications ? "Expanded" : "Collapsed")
                Button { model.refreshManually() } label: {
                    if model.isManualRefreshing {
                        ProgressView().controlSize(.mini).tint(.white)
                    } else if model.refreshFeedback != nil {
                        Image(systemName: model.refreshHadError ? "exclamationmark.circle" : "checkmark")
                            .foregroundStyle(.white)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .foregroundStyle(.white)
                    }
                }
                .keyboardShortcut("r")
                .disabled(model.isManualRefreshing)
                .help(model.lastManualRefreshAt.map { "Last refresh: \($0.formatted(date: .omitted, time: .standard)). Reload progress, read watched sessions, and check GitHub now." } ?? "Reload progress, read watched sessions, and check GitHub now")
            }
            if !setupDismissed && displayPlans.isEmpty {
                HStack(spacing: 10) {
                    Button(action: onSettings) {
                        Label("Set up Tracker Trapper…", systemImage: "exclamationmark.circle.fill")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    Spacer()
                    Button { setupDismissed = true } label: {
                        Image(systemName: "xmark")
                    }
                    .help("Dismiss setup reminder")
                    .accessibilityLabel("Dismiss setup reminder")
                }
                .foregroundStyle(.black)
                .tint(.black)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(Color(red: 0.94, green: 1.0, blue: 0.35), in: Capsule())
            }
            if let notice = AttentionNotice.current(model.snapshot).first {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "exclamationmark.circle.fill").font(.title3).foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Needs your attention").font(.system(size: 13, weight: .semibold))
                        Text(notice.body).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(3)
                    }
                    Spacer(minLength: 0)
                }.padding(13).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.orange.opacity(0.35)))
            }
            if showsNotifications { notificationDetails }
            if !displayPlans.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                ForEach(displayPlans) { plan in
                    Group {
                        if model.celebrations.pending.contains(where: { $0.id == plan.id })
                            && !model.celebrations.hasPendingTodo(for: plan.id) {
                            CompletionCelebrationCard(plan: plan, playing: model.celebratingID == plan.id,
                                                      isClosedIssue: model.celebrations.isClosedIssue(plan.id))
                        } else {
                            PlanCard(plan: plan, runs: model.snapshot.runs.filter { $0.planID == plan.id }, watches: model.watches, onLink: model.linkSession, onUnlink: model.unlinkSession)
                        }
                    }
                    .transition(reduceMotion ? .opacity : .asymmetric(insertion: .opacity, removal: .move(edge: .trailing).combined(with: .opacity).combined(with: .scale(scale: 0.92))))
                }
                }.id(model.revealID)
                Divider(); Text(footerText).font(.caption).foregroundStyle(.secondary)
            }
        }.padding(18).frame(width: 420)
        }.frame(width: 420)
        .trackerGlass(radius: 26, shell: true)
        .tint(.white)
        .buttonStyle(.borderless)
        .onChange(of: model.revealID) { _ in showsNotifications = false }
    }
    private var footerText: String {
        if !model.snapshot.plans.contains(where: \.isGitHub) {
            return "Local plans stay on this Mac."
        }
        return model.snapshot.outbox.isEmpty
            ? "No GitHub updates pending."
            : "\(model.snapshot.outbox.count) update(s) saved locally; GitHub sync pending."
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
        }.padding(14).trackerGlass(radius: 16)
    }
    private func attentionDescription(_ key: String) -> String {
        if let notice = AttentionNotice.current(model.snapshot).first(where: { $0.id == key }) {
            return "\(notice.subtitle): \(notice.body)"
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
    @State private var expandedStages: Set<String> = []
    let plan: Plan; let runs: [Run]
    let watches: [SessionWatch]
    let onLink: (Run) -> Void
    let onUnlink: (String) -> Void
    var completed: Int { plan.todos.filter { $0.status == .completed }.count }
    var visibleTodos: [Todo] {
        showsRemainingOnly ? plan.todos.filter { $0.status != .completed && $0.status != .skipped } : plan.todos
    }
    var stages: [String] {
        var seen: Set<String> = []
        return plan.todos.compactMap(\.stage).filter { seen.insert($0).inserted }
    }
    var linkedSessions: [SessionWatch] { watches.filter { watch in runs.contains { $0.id == watch.runID } } }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Button { showsRemainingOnly.toggle() } label: {
                    HStack {
                        Image(systemName: showsRemainingOnly ? "chevron.right" : "chevron.down")
                        Text(plan.displaySubtitle).font(.system(size: 12)).foregroundStyle(.secondary)
                            .lineLimit(1).truncationMode(.middle)
                    }.contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(showsRemainingOnly ? "Show all tasks" : "Show only remaining tasks")
                .accessibilityValue(showsRemainingOnly ? "Remaining tasks only" : "All tasks")
                Spacer(minLength: 2)

                if plan.isGitHub, let url = URL(string: plan.issueURL) {
                    Link(destination: url) {
                        GitHubMark().fill(.primary).frame(width: 15, height: 15)
                            .frame(width: 26, height: 26).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 5))
                    .help("Open issue on GitHub")
                    .accessibilityLabel("Open \(plan.repository) #\(plan.issueNumber) on GitHub")
                }
                ForEach(linkedSessions) { watch in
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: watch.sourcePath)])
                    } label: {
                        Group {
                            if watch.format == .claude { ClaudeMark().fill(Color.orange) }
                            else { OpenAIMark().fill(Color.primary) }
                        }.frame(width: 16, height: 16)
                            .frame(width: 26, height: 26).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 5))
                    .help("Reveal \(watch.format == .claude ? "Claude" : "Codex / GPT") session file: \(watch.sessionID)")
                    .accessibilityLabel("Reveal \(watch.format == .claude ? "Claude" : "Codex / GPT") session \(watch.sessionID) in Finder")
                }
                Group {
                    Button { onUnlink(plan.id) } label: {
                        Image(systemName: "xmark").font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.secondary).frame(width: 26, height: 26).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Stop watching and remove this plan from Tracker Trapper")
                    .accessibilityLabel("Stop watching \(plan.displaySubtitle) and remove its task list")
                }
            }
            Text(plan.title).font(.system(size: 17, weight: .bold)).tracking(-0.35).lineLimit(3).fixedSize(horizontal: false, vertical: true)
            if plan.source == .local, let workspacePath = plan.workspacePath, !workspacePath.isEmpty {
                Text(URL(fileURLWithPath: workspacePath).lastPathComponent).font(.caption).foregroundStyle(.secondary)
                    .help(workspacePath)
            }
            TrackerProgress(completed: completed, total: plan.todos.count).padding(.top, 6)
            Divider().overlay(Color.blue.opacity(0.05))
            ForEach(runs.filter { run in run.status == .active && !watches.contains { $0.runID == run.id } }) { run in
                HStack {
                    Spacer()
                    Button("Link session…") { onLink(run) }.font(.caption)
                        .accessibilityLabel("Link \(run.agent) session")
                }
            }
            ForEach(visibleTodos.filter { $0.stage == nil }) { todo in
                todoRow(todo)
            }
            ForEach(stages, id: \.self) { stage in
                let todos = plan.todos.filter { $0.stage == stage }
                let done = todos.allSatisfy { $0.status == .completed || $0.status == .skipped }
                let expanded = expandedStages.contains(stage)
                VStack(alignment: .leading, spacing: 6) {
                    Button {
                        if expanded { expandedStages.remove(stage) } else { expandedStages.insert(stage) }
                    } label: {
                        HStack {
                            Image(systemName: expanded ? "chevron.down" : "chevron.right")
                            Image(systemName: done ? "checkmark.square.fill" : "square")
                                .foregroundStyle(done ? .green : .secondary)
                            Text(stage).font(.subheadline.bold())
                            Spacer()
                            Text("\(todos.filter { $0.status == .completed || $0.status == .skipped }.count)/\(todos.count)")
                                .monospacedDigit().foregroundStyle(.secondary)
                        }.contentShape(Rectangle())
                    }.buttonStyle(.plain)
                    .accessibilityLabel("\(stage), \(done ? "complete" : "incomplete")")
                    .accessibilityValue(expanded ? "All tasks" : "Remaining tasks only")
                    ForEach(expanded ? todos : todos.filter { $0.status != .completed && $0.status != .skipped }) { todo in
                        todoRow(todo).padding(.leading, 18)
                    }
                }
                .onChange(of: done) { complete in
                    if complete { expandedStages.remove(stage) }
                }
            }
            if let run = runs.max(by: { $0.lastActivityAt < $1.lastActivityAt }) {
                Divider().padding(.top, 4)
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 7) {
                        Circle().fill(run.status == .active ? Color.green : Color.orange).frame(width: 6, height: 6)
                        Text("\(run.agent) · \(run.status.rawValue.replacingOccurrences(of: "_", with: " ").capitalized)")
                            .font(.system(size: 12))
                    }
                    Text("Activity updated \(run.lastActivityAt.formatted(.relative(presentation: .named)))")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
        }.padding(16).trackerGlass(radius: 18)
        .onChange(of: showsRemainingOnly) { remainingOnly in
            expandedStages = remainingOnly ? [] : Set(stages)
        }
    }
    private func todoRow(_ todo: Todo) -> some View {
        let isNext = plan.nextTodo?.id == todo.id
        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: isNext ? "circle.fill" : icon(for: todo.status))
                .foregroundStyle(isNext ? .blue : color(for: todo.status))
                .font(.system(size: 15)).frame(width: 18, height: 20)
                .help(isNext ? "Next task" : todo.status.rawValue)
            Text(todo.description).font(.system(size: 13)).strikethrough(todo.status == .completed)
                .foregroundStyle(todo.status == .completed ? .secondary : .primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(isNext ? "Next task, " : "")\(todo.status.rawValue): \(todo.description)")
    }
    func icon(for status: TodoStatus) -> String { switch status { case .completed: "checkmark.circle.fill"; case .inProgress: "circle.inset.filled"; case .blocked: "exclamationmark.triangle.fill"; case .skipped: "minus.circle"; case .pending: "square" } }
    func color(for status: TodoStatus) -> Color { switch status { case .completed: .green; case .inProgress: .blue; case .blocked: .orange; case .skipped: .secondary; case .pending: .secondary } }
}

struct CompletionCelebrationCard: View {
    let plan: Plan
    let playing: Bool
    var isClosedIssue = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var burst = false

    var body: some View {
        ZStack {
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
                Text(isClosedIssue ? "Issue closed!" : (plan.isGitHub ? "Issue complete!" : "List complete!")).font(.title2.bold())
                Text(plan.displaySubtitle).font(.subheadline.bold())
                Text(plan.title).font(.system(size: 13)).multilineTextAlignment(.center).lineLimit(3)
                if !isClosedIssue {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(plan.todos.filter { $0.status == .completed }.prefix(3)) { todo in
                            HStack(spacing: 9) {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                                Text(todo.description).strikethrough().foregroundStyle(.secondary).lineLimit(2)
                            }.font(.system(size: 12))
                        }
                    }.padding(.top, 15)
                }
            }
            .padding(18).frame(maxWidth: .infinity)
        }
        .frame(minHeight: 270)
        .trackerGlass(radius: 18)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(isClosedIssue ? "Issue closed" : "Plan complete"): \(plan.displaySubtitle), \(plan.title)")
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


// Simple Icons v14 (CC0): https://github.com/simple-icons/simple-icons/tree/14.0.0
struct OpenAIMark: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 22.2819000, y: 9.8211000))
        path.addCurve(to: CGPoint(x: 21.7662000, y: 4.9103000), control1: CGPoint(x: 22.8247763, y: 8.1862353), control2: CGPoint(x: 22.6368537, y: 6.3967250))
        path.addCurve(to: CGPoint(x: 15.2564000, y: 2.0103000), control1: CGPoint(x: 20.4570885, y: 2.6316330), control2: CGPoint(x: 17.8259794, y: 1.4595208))
        path.addCurve(to: CGPoint(x: 9.4919809, y: 0.1310784), control1: CGPoint(x: 13.8083290, y: 0.3995277), control2: CGPoint(x: 11.6111651, y: -0.3167557))
        path.addCurve(to: CGPoint(x: 4.9807000, y: 4.1818000), control1: CGPoint(x: 7.3727967, y: 0.5789124), control2: CGPoint(x: 5.6532786, y: 2.1228840))
        path.addCurve(to: CGPoint(x: 0.9830000, y: 7.0818000), control1: CGPoint(x: 3.2928034, y: 4.5279192), control2: CGPoint(x: 1.8359752, y: 5.5847273))
        path.addCurve(to: CGPoint(x: 1.7257000, y: 14.1784000), control1: CGPoint(x: -0.3404341, y: 9.3568411), control2: CGPoint(x: -0.0400906, y: 12.2266640))
        path.addCurve(to: CGPoint(x: 2.2367000, y: 19.0891000), control1: CGPoint(x: 1.1808155, y: 15.8124986), control2: CGPoint(x: 1.3670487, y: 17.6021959))
        path.addCurve(to: CGPoint(x: 8.7513000, y: 21.9892000), control1: CGPoint(x: 3.5474532, y: 21.3685811), control2: CGPoint(x: 6.1803050, y: 22.5406460))
        path.addCurve(to: CGPoint(x: 13.2599000, y: 24.0000000), control1: CGPoint(x: 9.8948383, y: 23.2769626), control2: CGPoint(x: 11.5377157, y: 24.0096730))
        path.addCurve(to: CGPoint(x: 19.0317000, y: 19.7942000), control1: CGPoint(x: 15.8937384, y: 24.0024236), control2: CGPoint(x: 18.2271138, y: 22.3021377))
        path.addCurve(to: CGPoint(x: 23.0294000, y: 16.8941000), control1: CGPoint(x: 20.7193622, y: 19.4474844), control2: CGPoint(x: 22.1759797, y: 18.3907928))
        path.addCurve(to: CGPoint(x: 22.2819000, y: 9.8212000), control1: CGPoint(x: 24.3368029, y: 14.6230652), control2: CGPoint(x: 24.0351465, y: 11.7687699))
        path.addLine(to: CGPoint(x: 22.2819000, y: 9.8211000))
        path.closeSubpath()
        path.move(to: CGPoint(x: 13.2599000, y: 22.4292000))
        path.addCurve(to: CGPoint(x: 10.3835000, y: 21.3884000), control1: CGPoint(x: 12.2086176, y: 22.4308640), control2: CGPoint(x: 11.1903011, y: 22.0623951))
        path.addLine(to: CGPoint(x: 10.5254000, y: 21.3080000))
        path.addLine(to: CGPoint(x: 15.3037000, y: 18.5498000))
        path.addCurve(to: CGPoint(x: 15.6964000, y: 17.8685000), control1: CGPoint(x: 15.5456463, y: 18.4079018), control2: CGPoint(x: 15.6948865, y: 18.1489832))
        path.addLine(to: CGPoint(x: 15.6964000, y: 11.1316000))
        path.addLine(to: CGPoint(x: 17.7164000, y: 12.3002000))
        path.addCurve(to: CGPoint(x: 17.7544000, y: 12.3522000), control1: CGPoint(x: 17.7366519, y: 12.3104610), control2: CGPoint(x: 17.7507756, y: 12.3297881))
        path.addLine(to: CGPoint(x: 17.7544000, y: 17.9348000))
        path.addCurve(to: CGPoint(x: 13.2599000, y: 22.4292000), control1: CGPoint(x: 17.7491194, y: 20.4148370), control2: CGPoint(x: 15.7399371, y: 22.4239746))
        path.addLine(to: CGPoint(x: 13.2599000, y: 22.4292000))
        path.closeSubpath()
        path.move(to: CGPoint(x: 3.5992000, y: 18.3038000))
        path.addCurve(to: CGPoint(x: 3.0646000, y: 15.2901000), control1: CGPoint(x: 3.0719725, y: 17.3934203), control2: CGPoint(x: 2.8826720, y: 16.3262767))
        path.addLine(to: CGPoint(x: 3.2066000, y: 15.3753000))
        path.addLine(to: CGPoint(x: 7.9896000, y: 18.1335000))
        path.addCurve(to: CGPoint(x: 8.7702000, y: 18.1335000), control1: CGPoint(x: 8.2305873, y: 18.2749092), control2: CGPoint(x: 8.5292127, y: 18.2749092))
        path.addLine(to: CGPoint(x: 14.6130000, y: 14.7650000))
        path.addLine(to: CGPoint(x: 14.6130000, y: 17.0974000))
        path.addCurve(to: CGPoint(x: 14.5798000, y: 17.1589000), control1: CGPoint(x: 14.6118880, y: 17.1218894), control2: CGPoint(x: 14.5996639, y: 17.1445335))
        path.addLine(to: CGPoint(x: 9.7400000, y: 19.9502000))
        path.addCurve(to: CGPoint(x: 3.5992000, y: 18.3038000), control1: CGPoint(x: 7.5893410, y: 21.1891380), control2: CGPoint(x: 4.8416181, y: 20.4524504))
        path.addLine(to: CGPoint(x: 3.5992000, y: 18.3038000))
        path.closeSubpath()
        path.move(to: CGPoint(x: 2.3408000, y: 7.8956000))
        path.addCurve(to: CGPoint(x: 4.7063000, y: 5.9228000), control1: CGPoint(x: 2.8716834, y: 6.9793690), control2: CGPoint(x: 3.7096324, y: 6.2805291))
        path.addLine(to: CGPoint(x: 4.7063000, y: 11.6000000))
        path.addCurve(to: CGPoint(x: 5.0942000, y: 12.2765000), control1: CGPoint(x: 4.7026368, y: 11.8793443), control2: CGPoint(x: 4.8512652, y: 12.1385531))
        path.addLine(to: CGPoint(x: 10.9086000, y: 15.6308000))
        path.addLine(to: CGPoint(x: 8.8885000, y: 16.7993000))
        path.addCurve(to: CGPoint(x: 8.8175000, y: 16.7993000), control1: CGPoint(x: 8.8663009, y: 16.8110869), control2: CGPoint(x: 8.8396991, y: 16.8110869))
        path.addLine(to: CGPoint(x: 3.9872000, y: 14.0128000))
        path.addCurve(to: CGPoint(x: 2.3408000, y: 7.8720000), control1: CGPoint(x: 1.8408159, y: 12.7686447), control2: CGPoint(x: 1.1046934, y: 10.0230294))
        path.addLine(to: CGPoint(x: 2.3408000, y: 7.8956000))
        path.closeSubpath()
        path.move(to: CGPoint(x: 18.9371000, y: 11.7514000))
        path.addLine(to: CGPoint(x: 13.1038000, y: 8.3640000))
        path.addLine(to: CGPoint(x: 15.1192000, y: 7.2000000))
        path.addCurve(to: CGPoint(x: 15.1902000, y: 7.2000000), control1: CGPoint(x: 15.1413991, y: 7.1882131), control2: CGPoint(x: 15.1680009, y: 7.1882131))
        path.addLine(to: CGPoint(x: 20.0205000, y: 9.9913000))
        path.addCurve(to: CGPoint(x: 22.2531057, y: 14.2580028), control1: CGPoint(x: 21.5281238, y: 10.8612194), control2: CGPoint(x: 22.3978992, y: 12.5234354))
        path.addCurve(to: CGPoint(x: 19.3440000, y: 18.0955000), control1: CGPoint(x: 22.1083123, y: 15.9925702), control2: CGPoint(x: 20.9749870, y: 17.4875769))
        path.addLine(to: CGPoint(x: 19.3440000, y: 12.4183000))
        path.addCurve(to: CGPoint(x: 18.9370000, y: 11.7513000), control1: CGPoint(x: 19.3354792, y: 12.1397415), control2: CGPoint(x: 19.1808188, y: 11.8862809))
        path.addLine(to: CGPoint(x: 18.9371000, y: 11.7514000))
        path.closeSubpath()
        path.move(to: CGPoint(x: 20.9478000, y: 8.7283000))
        path.addLine(to: CGPoint(x: 20.8058000, y: 8.6431000))
        path.addLine(to: CGPoint(x: 16.0323000, y: 5.8613000))
        path.addCurve(to: CGPoint(x: 15.2469000, y: 5.8613000), control1: CGPoint(x: 15.7898333, y: 5.7190123), control2: CGPoint(x: 15.4893667, y: 5.7190123))
        path.addLine(to: CGPoint(x: 9.4090000, y: 9.2297000))
        path.addLine(to: CGPoint(x: 9.4090000, y: 6.8974000))
        path.addCurve(to: CGPoint(x: 9.4374000, y: 6.8359000), control1: CGPoint(x: 9.4064669, y: 6.8732422), control2: CGPoint(x: 9.4173674, y: 6.8496372))
        path.addLine(to: CGPoint(x: 14.2677000, y: 4.0493000))
        path.addCurve(to: CGPoint(x: 19.0877365, y: 4.2577824), control1: CGPoint(x: 15.7789777, y: 3.1786744), control2: CGPoint(x: 17.6572772, y: 3.2599171))
        path.addCurve(to: CGPoint(x: 20.9479000, y: 8.7093000), control1: CGPoint(x: 20.5181958, y: 5.2556478), control2: CGPoint(x: 21.2430750, y: 6.9903408))
        path.addLine(to: CGPoint(x: 20.9478000, y: 8.7283000))
        path.closeSubpath()
        path.move(to: CGPoint(x: 8.3065000, y: 12.8630000))
        path.addLine(to: CGPoint(x: 6.2865000, y: 11.6992000))
        path.addCurve(to: CGPoint(x: 6.2485000, y: 11.6425000), control1: CGPoint(x: 6.2660412, y: 11.6868815), control2: CGPoint(x: 6.2521173, y: 11.6661056))
        path.addLine(to: CGPoint(x: 6.2485000, y: 6.0742000))
        path.addCurve(to: CGPoint(x: 8.8397409, y: 2.0054384), control1: CGPoint(x: 6.2507696, y: 4.3303879), control2: CGPoint(x: 7.2604882, y: 2.7449295))
        path.addCurve(to: CGPoint(x: 13.6242000, y: 2.6205000), control1: CGPoint(x: 10.4189935, y: 1.2659473), control2: CGPoint(x: 12.2833348, y: 1.5056159))
        path.addLine(to: CGPoint(x: 13.4822000, y: 2.7010000))
        path.addLine(to: CGPoint(x: 8.7040000, y: 5.4590000))
        path.addCurve(to: CGPoint(x: 8.3113000, y: 6.1403000), control1: CGPoint(x: 8.4620537, y: 5.6008982), control2: CGPoint(x: 8.3128135, y: 5.8598168))
        path.addLine(to: CGPoint(x: 8.3065000, y: 12.8630000))
        path.closeSubpath()
        path.move(to: CGPoint(x: 9.4041000, y: 10.4976000))
        path.addLine(to: CGPoint(x: 12.0061000, y: 8.9978000))
        path.addLine(to: CGPoint(x: 14.6130000, y: 10.4976000))
        path.addLine(to: CGPoint(x: 14.6130000, y: 13.4970000))
        path.addLine(to: CGPoint(x: 12.0156000, y: 14.9967000))
        path.addLine(to: CGPoint(x: 9.4089000, y: 13.4970000))
        path.addLine(to: CGPoint(x: 9.4041000, y: 10.4976000))
        path.closeSubpath()
        return path.applying(CGAffineTransform(scaleX: rect.width / 24, y: rect.height / 24))
    }
}

struct ClaudeMark: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 4.7144000, y: 15.9555000))
        path.addLine(to: CGPoint(x: 9.4318000, y: 13.3084000))
        path.addLine(to: CGPoint(x: 9.5108000, y: 13.0777000))
        path.addLine(to: CGPoint(x: 9.4318000, y: 12.9502000))
        path.addLine(to: CGPoint(x: 9.2011000, y: 12.9502000))
        path.addLine(to: CGPoint(x: 8.4118000, y: 12.9016000))
        path.addLine(to: CGPoint(x: 5.7162000, y: 12.8287000))
        path.addLine(to: CGPoint(x: 3.3787000, y: 12.7316000))
        path.addLine(to: CGPoint(x: 1.1141000, y: 12.6102000))
        path.addLine(to: CGPoint(x: 0.5434000, y: 12.4887000))
        path.addLine(to: CGPoint(x: 0.0091000, y: 11.7845000))
        path.addLine(to: CGPoint(x: 0.0637000, y: 11.4323000))
        path.addLine(to: CGPoint(x: 0.5434000, y: 11.1105000))
        path.addLine(to: CGPoint(x: 1.2294000, y: 11.1713000))
        path.addLine(to: CGPoint(x: 2.7473000, y: 11.2745000))
        path.addLine(to: CGPoint(x: 5.0240000, y: 11.4323000))
        path.addLine(to: CGPoint(x: 6.6754000, y: 11.5295000))
        path.addLine(to: CGPoint(x: 9.1222000, y: 11.7845000))
        path.addLine(to: CGPoint(x: 9.5108000, y: 11.7845000))
        path.addLine(to: CGPoint(x: 9.5654000, y: 11.6266000))
        path.addLine(to: CGPoint(x: 9.4318000, y: 11.5295000))
        path.addLine(to: CGPoint(x: 9.3286000, y: 11.4323000))
        path.addLine(to: CGPoint(x: 6.9730000, y: 9.8356000))
        path.addLine(to: CGPoint(x: 4.4230000, y: 8.1477000))
        path.addLine(to: CGPoint(x: 3.0874000, y: 7.1763000))
        path.addLine(to: CGPoint(x: 2.3649000, y: 6.6845000))
        path.addLine(to: CGPoint(x: 2.0006000, y: 6.2231000))
        path.addLine(to: CGPoint(x: 1.8428000, y: 5.2153000))
        path.addLine(to: CGPoint(x: 2.4985000, y: 4.4928000))
        path.addLine(to: CGPoint(x: 3.3788000, y: 4.5535000))
        path.addLine(to: CGPoint(x: 3.6034000, y: 4.6142000))
        path.addLine(to: CGPoint(x: 4.4959000, y: 5.3002000))
        path.addLine(to: CGPoint(x: 6.4023000, y: 6.7756000))
        path.addLine(to: CGPoint(x: 8.8916000, y: 8.6092000))
        path.addLine(to: CGPoint(x: 9.2559000, y: 8.9127000))
        path.addLine(to: CGPoint(x: 9.4016000, y: 8.8095000))
        path.addLine(to: CGPoint(x: 9.4198000, y: 8.7367000))
        path.addLine(to: CGPoint(x: 9.2558000, y: 8.4634000))
        path.addLine(to: CGPoint(x: 7.9019000, y: 6.0167000))
        path.addLine(to: CGPoint(x: 6.4569000, y: 3.5274000))
        path.addLine(to: CGPoint(x: 5.8134000, y: 2.4954000))
        path.addLine(to: CGPoint(x: 5.6434000, y: 1.8760000))
        path.addCurve(to: CGPoint(x: 5.5402000, y: 1.1475000), control1: CGPoint(x: 5.5827000, y: 1.6210000), control2: CGPoint(x: 5.5402000, y: 1.4086000))
        path.addLine(to: CGPoint(x: 6.2870000, y: 0.1335000))
        path.addLine(to: CGPoint(x: 6.6997000, y: 0.0000000))
        path.addLine(to: CGPoint(x: 7.6954000, y: 0.1336000))
        path.addLine(to: CGPoint(x: 8.1144000, y: 0.4978000))
        path.addLine(to: CGPoint(x: 8.7336000, y: 1.9125000))
        path.addLine(to: CGPoint(x: 9.7354000, y: 4.1407000))
        path.addLine(to: CGPoint(x: 11.2897000, y: 7.1703000))
        path.addLine(to: CGPoint(x: 11.7450000, y: 8.0688000))
        path.addLine(to: CGPoint(x: 11.9879000, y: 8.9006000))
        path.addLine(to: CGPoint(x: 12.0789000, y: 9.1556000))
        path.addLine(to: CGPoint(x: 12.2368000, y: 9.1556000))
        path.addLine(to: CGPoint(x: 12.2368000, y: 9.0099000))
        path.addLine(to: CGPoint(x: 12.3643000, y: 7.3039000))
        path.addLine(to: CGPoint(x: 12.6011000, y: 5.2092000))
        path.addLine(to: CGPoint(x: 12.8318000, y: 2.5135000))
        path.addLine(to: CGPoint(x: 12.9107000, y: 1.7546000))
        path.addLine(to: CGPoint(x: 13.2871000, y: 0.8439000))
        path.addLine(to: CGPoint(x: 14.0339000, y: 0.3521000))
        path.addLine(to: CGPoint(x: 14.6167000, y: 0.6314000))
        path.addLine(to: CGPoint(x: 15.0964000, y: 1.3174000))
        path.addLine(to: CGPoint(x: 15.0296000, y: 1.7607000))
        path.addLine(to: CGPoint(x: 14.7443000, y: 3.6124000))
        path.addLine(to: CGPoint(x: 14.1857000, y: 6.5145000))
        path.addLine(to: CGPoint(x: 13.8214000, y: 8.4574000))
        path.addLine(to: CGPoint(x: 14.0339000, y: 8.4574000))
        path.addLine(to: CGPoint(x: 14.2768000, y: 8.2145000))
        path.addLine(to: CGPoint(x: 15.2603000, y: 6.9092000))
        path.addLine(to: CGPoint(x: 16.9117000, y: 4.8449000))
        path.addLine(to: CGPoint(x: 17.6403000, y: 4.0253000))
        path.addLine(to: CGPoint(x: 18.4903000, y: 3.1207000))
        path.addLine(to: CGPoint(x: 19.0367000, y: 2.6896000))
        path.addLine(to: CGPoint(x: 20.0688000, y: 2.6896000))
        path.addLine(to: CGPoint(x: 20.8278000, y: 3.8189000))
        path.addLine(to: CGPoint(x: 20.4878000, y: 4.9846000))
        path.addLine(to: CGPoint(x: 19.4253000, y: 6.3324000))
        path.addLine(to: CGPoint(x: 18.5449000, y: 7.4738000))
        path.addLine(to: CGPoint(x: 17.2821000, y: 9.1738000))
        path.addLine(to: CGPoint(x: 16.4928000, y: 10.5338000))
        path.addLine(to: CGPoint(x: 16.5657000, y: 10.6431000))
        path.addLine(to: CGPoint(x: 16.7539000, y: 10.6248000))
        path.addLine(to: CGPoint(x: 19.6074000, y: 10.0178000))
        path.addLine(to: CGPoint(x: 21.1495000, y: 9.7384000))
        path.addLine(to: CGPoint(x: 22.9891000, y: 9.4227000))
        path.addLine(to: CGPoint(x: 23.8209000, y: 9.8113000))
        path.addLine(to: CGPoint(x: 23.9119000, y: 10.2059000))
        path.addLine(to: CGPoint(x: 23.5841000, y: 11.0134000))
        path.addLine(to: CGPoint(x: 21.6171000, y: 11.4991000))
        path.addLine(to: CGPoint(x: 19.3099000, y: 11.9605000))
        path.addLine(to: CGPoint(x: 15.8735000, y: 12.7741000))
        path.addLine(to: CGPoint(x: 15.8310000, y: 12.8045000))
        path.addLine(to: CGPoint(x: 15.8796000, y: 12.8652000))
        path.addLine(to: CGPoint(x: 17.4278000, y: 13.0109000))
        path.addLine(to: CGPoint(x: 18.0896000, y: 13.0473000))
        path.addLine(to: CGPoint(x: 19.7106000, y: 13.0473000))
        path.addLine(to: CGPoint(x: 22.7281000, y: 13.2720000))
        path.addLine(to: CGPoint(x: 23.5173000, y: 13.7940000))
        path.addLine(to: CGPoint(x: 23.9909000, y: 14.4316000))
        path.addLine(to: CGPoint(x: 23.9119000, y: 14.9173000))
        path.addLine(to: CGPoint(x: 22.6977000, y: 15.5366000))
        path.addLine(to: CGPoint(x: 21.0584000, y: 15.1480000))
        path.addLine(to: CGPoint(x: 17.2334000, y: 14.2373000))
        path.addLine(to: CGPoint(x: 15.9221000, y: 13.9094000))
        path.addLine(to: CGPoint(x: 15.7399000, y: 13.9094000))
        path.addLine(to: CGPoint(x: 15.7399000, y: 14.0187000))
        path.addLine(to: CGPoint(x: 16.8328000, y: 15.0873000))
        path.addLine(to: CGPoint(x: 18.8363000, y: 16.8965000))
        path.addLine(to: CGPoint(x: 21.3438000, y: 19.2279000))
        path.addLine(to: CGPoint(x: 21.4713000, y: 19.8047000))
        path.addLine(to: CGPoint(x: 21.1495000, y: 20.2601000))
        path.addLine(to: CGPoint(x: 20.8095000, y: 20.2115000))
        path.addLine(to: CGPoint(x: 18.6056000, y: 18.5540000))
        path.addLine(to: CGPoint(x: 17.7556000, y: 17.8072000))
        path.addLine(to: CGPoint(x: 15.8310000, y: 16.1862000))
        path.addLine(to: CGPoint(x: 15.7035000, y: 16.1862000))
        path.addLine(to: CGPoint(x: 15.7035000, y: 16.3562000))
        path.addLine(to: CGPoint(x: 16.1467000, y: 17.0058000))
        path.addLine(to: CGPoint(x: 18.4903000, y: 20.5272000))
        path.addLine(to: CGPoint(x: 18.6117000, y: 21.6079000))
        path.addLine(to: CGPoint(x: 18.4417000, y: 21.9600000))
        path.addLine(to: CGPoint(x: 17.8346000, y: 22.1725000))
        path.addLine(to: CGPoint(x: 17.1667000, y: 22.0511000))
        path.addLine(to: CGPoint(x: 15.7946000, y: 20.1265000))
        path.addLine(to: CGPoint(x: 14.3800000, y: 17.9590000))
        path.addLine(to: CGPoint(x: 13.2386000, y: 16.0162000))
        path.addLine(to: CGPoint(x: 13.0989000, y: 16.0952000))
        path.addLine(to: CGPoint(x: 12.4249000, y: 23.3504000))
        path.addLine(to: CGPoint(x: 12.1093000, y: 23.7207000))
        path.addLine(to: CGPoint(x: 11.3807000, y: 24.0000000))
        path.addLine(to: CGPoint(x: 10.7736000, y: 23.5386000))
        path.addLine(to: CGPoint(x: 10.4518000, y: 22.7918000))
        path.addLine(to: CGPoint(x: 10.7736000, y: 21.3165000))
        path.addLine(to: CGPoint(x: 11.1622000, y: 19.3919000))
        path.addLine(to: CGPoint(x: 11.4779000, y: 17.8619000))
        path.addLine(to: CGPoint(x: 11.7632000, y: 15.9615000))
        path.addLine(to: CGPoint(x: 11.9332000, y: 15.3301000))
        path.addLine(to: CGPoint(x: 11.9211000, y: 15.2876000))
        path.addLine(to: CGPoint(x: 11.7814000, y: 15.3058000))
        path.addLine(to: CGPoint(x: 10.3486000, y: 17.2730000))
        path.addLine(to: CGPoint(x: 8.1690000, y: 20.2176000))
        path.addLine(to: CGPoint(x: 6.4447000, y: 22.0632000))
        path.addLine(to: CGPoint(x: 6.0319000, y: 22.2272000))
        path.addLine(to: CGPoint(x: 5.3155000, y: 21.8568000))
        path.addLine(to: CGPoint(x: 5.3822000, y: 21.1950000))
        path.addLine(to: CGPoint(x: 5.7830000, y: 20.6061000))
        path.addLine(to: CGPoint(x: 8.1690000, y: 17.5704000))
        path.addLine(to: CGPoint(x: 9.6079000, y: 15.6884000))
        path.addLine(to: CGPoint(x: 10.5369000, y: 14.6016000))
        path.addLine(to: CGPoint(x: 10.5307000, y: 14.4437000))
        path.addLine(to: CGPoint(x: 10.4761000, y: 14.4437000))
        path.addLine(to: CGPoint(x: 4.1376000, y: 18.5601000))
        path.addLine(to: CGPoint(x: 3.0083000, y: 18.7058000))
        path.addLine(to: CGPoint(x: 2.5226000, y: 18.2504000))
        path.addLine(to: CGPoint(x: 2.5834000, y: 17.5037000))
        path.addLine(to: CGPoint(x: 2.8141000, y: 17.2608000))
        path.addLine(to: CGPoint(x: 4.7205000, y: 15.9494000))
        path.addLine(to: CGPoint(x: 4.7144000, y: 15.9555000))
        path.closeSubpath()
        return path.applying(CGAffineTransform(scaleX: rect.width / 24, y: rect.height / 24))
    }
}
