import AppKit
import SwiftUI
import ServiceManagement
import TrackerTrapperCore

@MainActor final class TrackerSettingsWindow: NSWindowController {
    init(model: MenuModel, notifications: NotificationService = .shared,
         onTestCheckboxPopup: @escaping () -> Void = {},
         onTestTaskListPopup: @escaping () -> Void = {}) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 580),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Tracker Trapper Settings"
        window.identifier = NSUserInterfaceItemIdentifier("tracker-trapper-settings")
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(rootView: SettingsView(
            model: model,
            notifications: notifications,
            onTestCheckboxPopup: onTestCheckboxPopup,
            onTestTaskListPopup: onTestTaskListPopup
        ))
        super.init(window: window)
        window.center()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func reveal() {
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

@MainActor final class SetupModel: ObservableObject {
    @Published var preview: Plan?
    @Published var result: String?
    @Published var busy = false

    static func issue(_ text: String) throws -> Plan {
        guard let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme == "https", url.host == "github.com", url.user == nil, url.password == nil else {
            throw StoreError.conflict("Paste an https://github.com/owner/repository/issues/123 URL.")
        }
        let parts = url.path.split(separator: "/")
        guard parts.count == 4, parts[2] == "issues", let number = Int(parts[3]), number > 0 else {
            throw StoreError.conflict("Use an issue URL, not a repository or pull request URL.")
        }
        let repository = "\(parts[0])/\(parts[1])"
        return Plan(id: "github:\(repository)#\(number)", repository: repository, issueNumber: number,
                    issueURL: "https://github.com/\(repository)/issues/\(number)", title: "", todos: [])
    }
    func load(_ text: String) async {
        guard !busy else { return }
        busy = true; preview = nil; result = nil
        defer { busy = false }
        do {
            var plan = try Self.issue(text)
            let details = try await GitHubIssueStatus.details(plan)
            guard !details.isClosed else { throw StoreError.conflict("This issue is closed. Choose an open issue to track.") }
            plan.title = details.title ?? "GitHub issue"
            plan.todos = GitHubChecklist.parse(details.body ?? "")
            guard !plan.todos.isEmpty else { throw StoreError.conflict("No stable TT task IDs found. See the checklist example below.") }
            preview = plan
            result = "GitHub access verified. Review \(plan.todos.count) recognized tasks before importing."
        } catch { result = error.localizedDescription }
    }
    func importPreview(into store: TrackerStore?) async {
        guard !busy, let preview, let store else { return }
        busy = true; defer { busy = false }
        do {
            let existing = try await store.read().plans.first { $0.repository == preview.repository && $0.issueNumber == preview.issueNumber }
            if let existing {
                try await store.reconcileGitHubChecklist(planID: existing.id, title: preview.title, todos: preview.todos)
            } else { try await store.register(preview) }
            result = "Imported locally. Give your agent this issue URL and the reporting instruction."
            self.preview = nil
        } catch { result = error.localizedDescription }
    }
}

struct SettingsView: View {
    @ObservedObject var model: MenuModel
    @ObservedObject var notifications: NotificationService = .shared
    @ObservedObject var shortcutSettings: KeyboardShortcutSettings = .shared
    var onTestCheckboxPopup: () -> Void = {}
    var onTestTaskListPopup: () -> Void = {}
    @StateObject private var setup = SetupModel()
    @AppStorage("notifications.enabled") private var enabled = true
    @AppStorage("notifications.completions") private var completions = true
    @AppStorage("notifications.attention") private var attention = true
    @AppStorage("notifications.stale") private var stale = true
    @AppStorage("notifications.sound") private var sound = true
    @AppStorage("celebrations.enabled") private var celebrations = true
    @AppStorage("setup.dismissed") private var setupDismissed = false
    @AppStorage("setup.mcpPath") private var selectedMCPPath = ""
    @State private var provider = "Codex"
    @State private var issueURL = ""
    @State private var loginStatus = SMAppService.mainApp.status
    @State private var loginError: String?
    @State private var loginBusy = false
    @State private var tab = "notifications"
    private var storeURL: URL { model.store?.url ?? TrackerStore.defaultURL() }
    private var mcpPath: String {
        if !selectedMCPPath.isEmpty { return selectedMCPPath }
        let root = Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent()
        return root.appendingPathComponent(".build/release/tracker-trapper-mcp").path
    }
    private var executableExists: Bool { FileManager.default.isExecutableFile(atPath: mcpPath) }
    private var permanentInstall: Bool {
        let path = Bundle.main.bundleURL.resolvingSymlinksInPath().path
        return path.hasPrefix("/Applications/") || path.hasPrefix(NSHomeDirectory() + "/Applications/")
    }
    private var setupCommand: String {
        let path = "'" + mcpPath.replacingOccurrences(of: "'", with: "'\\''") + "'"
        return provider == "Codex" ? "codex mcp add tracker-trapper -- \(path)" : "claude mcp add --transport stdio --scope user tracker-trapper -- \(path)"
    }
    static let agentReportingInstruction = """
    Use Tracker Trapper for this issue. Retrieve its plan and stable todo IDs; register the agreed checklist if absent. Start your own session run.

    Planning contract: make the plan itself Tracker Trapper-ready before implementation begins; do not write a prose plan and translate it afterward. Every plan item must map one-to-one to a persistent TT todo with a stable ID, one imperative outcome, and a concrete pass/fail acceptance check. Use the same ID and outcome wording in the plan and all Tracker Trapper updates. Create the smallest useful independently verifiable items. Split implementation, tests, build, install, runtime verification, and user acceptance when they are genuinely separate gates; combine trivial steps. Avoid vague outcomes, chronological narration, and bookkeeping-only todos. Preserve IDs when wording or order changes, and add a new ID when scope grows.

    Call start_task before each todo, report activity at milestones, and complete_task only after that todo's acceptance check passes with concrete evidence. Report blockers and the next immediate task. Finish your own run with its actual status. Do not close the issue without acceptance. First verify the connection with get_plan for an existing plan ID.
    """
    private var reportingInstruction: String { Self.agentReportingInstruction }
    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $tab) {
                AppearancePane().tabItem { Label("Appearance", systemImage: "paintpalette") }.tag("appearance")
                notificationPane.tabItem { Label("Notifications", systemImage: "bell") }.tag("notifications")
                generalPane.tabItem { Label("General", systemImage: "gearshape") }.tag("general")
                setupPane.tabItem { Label("Setup", systemImage: "checklist") }.tag("setup")
                aboutPane.tabItem { Label("Diagnostics", systemImage: "info.circle") }.tag("about")
            }
            Divider()
            HStack {
                Text("Tracker Trapper").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Quit Tracker Trapper") { NSApp.terminate(nil) }
            }.padding(12)
        }
        .frame(minWidth: 580, idealWidth: 640, minHeight: 480, idealHeight: 580)
        .task { await notifications.refresh(); loginStatus = SMAppService.mainApp.status }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await notifications.refresh(); loginStatus = SMAppService.mainApp.status }
        }
    }
    private var notificationPane: some View {
        Form {
            Section("macOS permission") {
                LabeledContent("Notifications", value: notifications.statusText)
                LabeledContent("Presentation", value: notifications.alertText)
                LabeledContent("System sound setting", value: notifications.soundText)
                if notifications.state?.authorization == .notDetermined {
                    Text("Allow alerts when work completes or needs your attention.")
                    Button("Enable Notifications") { Task { await notifications.requestPermission() } }
                        .disabled(notifications.isRequesting)
                }
                Button("Open macOS Notification Settings") { notifications.openSystemSettings() }
                Text("System Settings → Notifications → Tracker Trapper. Focus and screen sharing can also hide banners.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("What to notify") {
                Toggle("Enable notifications", isOn: $enabled)
                Group {
                    Toggle("Completed tasks", isOn: $completions)
                    Toggle("Needs attention, including blocked tasks", isOn: $attention)
                    Toggle("No activity for 15 minutes", isOn: $stale)
                    Toggle("Notification sound", isOn: $sound)
                }.disabled(!enabled)
            }
            Section("Test notifications and popups") {
                Button("Send Test Notification") { Task { await notifications.sendTest() } }
                    .disabled(!enabled || notifications.state == nil)
                Button("Show Test Checkbox Popup") { onTestCheckboxPopup() }
                Button("Show Test Finished Task List Popup") { onTestTaskListPopup() }
                if let date = notifications.lastAttempt { Text("Last attempt: \(date.formatted())").font(.caption) }
                Text(notifications.lastResult ?? "No notification attempts in this app session.")
                    .font(.caption).textSelection(.enabled)
            }
        }.formStyle(.grouped)
    }
    private var generalPane: some View {
        Form {
            Section("Behavior") {
                Toggle("Show completion celebrations", isOn: $celebrations)
                Text("A checkbox popout marks each completed task, followed by the larger celebration when its plan finishes. Closed issues also celebrate without interrupting your typing. Reduce Motion keeps the effects still.").font(.caption)
                LabeledContent("Show or hide panel") {
                    HStack {
                        KeyboardShortcutRecorder(shortcut: $shortcutSettings.shortcut)
                            .frame(width: 132, height: 26)
                        Button("Reset") { shortcutSettings.reset() }
                            .disabled(shortcutSettings.shortcut == .defaultShortcut)
                    }
                }
                Text("Click the shortcut, then press a key with Command, Option, or Control.")
                    .font(.caption).foregroundStyle(.secondary)
                if let error = shortcutSettings.registrationError {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
            }
            Section("Launch at login") {
                Text(loginDescription)
                if permanentInstall || loginStatus == .enabled || loginStatus == .requiresApproval {
                    Button(loginStatus == .notRegistered ? "Enable Launch at Login" : "Disable Launch at Login") {
                        loginBusy = true
                        Task {
                            defer { loginBusy = false; loginStatus = SMAppService.mainApp.status }
                            do {
                                if loginStatus == .notRegistered { try SMAppService.mainApp.register() }
                                else { try await SMAppService.mainApp.unregister() }
                                loginError = nil
                            } catch { loginError = error.localizedDescription }
                        }
                    }.disabled(loginBusy || loginStatus == .notFound)
                } else {
                    Text("This copy runs from a development folder. Install the app in Applications before enabling automatic launch; a Finder alias does not move the app.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Button("Open Login Items Settings") { SMAppService.openSystemSettingsLoginItems() }
                if let loginError { Text(loginError).foregroundStyle(.red) }
            }
        }.formStyle(.grouped)
    }
    private var loginDescription: String {
        switch loginStatus {
        case .enabled: "Enabled"
        case .requiresApproval: "Approval required in macOS Login Items Settings"
        case .notFound: "Login service unavailable for this app bundle"
        case .notRegistered: "Not enabled"
        @unknown default: "Unknown system status"
        }
    }
    private var setupPane: some View {
        Form {
            Section("1. Find Tracker Trapper") {
                Text("Click the checklist in your menu bar or press \(shortcutSettings.shortcut.displayName). Keep the app running to observe progress.")
                Toggle("Show a setup reminder when no issues are visible", isOn: Binding(get: { !setupDismissed }, set: { setupDismissed = !$0 }))
            }
            Section("2. Check notifications") {
                LabeledContent("Permission", value: notifications.statusText)
                Button("Notification settings and test") { tab = "notifications" }
            }
            Section("3. Connect your agent") {
                Picker("Agent", selection: $provider) { Text("Codex").tag("Codex"); Text("Claude Code").tag("Claude Code") }
                Text(executableExists ? "Local MCP executable found" : "Select the tracker-trapper-mcp executable from your build folder.")
                Text(mcpPath).font(.caption).textSelection(.enabled)
                Button("Choose MCP Executable…") {
                    let panel = NSOpenPanel(); panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
                    if panel.runModal() == .OK, let url = panel.url { selectedMCPPath = url.path }
                }
                if executableExists {
                    Text(setupCommand).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                    Button("Copy connection command") { copy(setupCommand) }
                }
                Text("If tracker-trapper is already configured, check its executable path instead of adding it again. Restart/reconnect the agent, then ask it to call get_plan. A successful tool result verifies the connection; finding this executable alone does not.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Copy agent reporting instruction") { copy(reportingInstruction) }
                if let plan = model.snapshot.plans.first {
                    Text("Example plan ID: \(plan.id)").font(.caption).textSelection(.enabled)
                }
                if let run = model.snapshot.runs.filter({ $0.agent.localizedCaseInsensitiveContains(provider == "Codex" ? "codex" : "claude") }).max(by: { $0.lastActivityAt < $1.lastActivityAt }) {
                    Text("Reporting observed: \(run.lastActivityAt.formatted()) (\(run.status.rawValue)). This is recorded activity, not a live connection test.").font(.caption)
                } else { Text("No reporting observed from this agent in the visible issues yet.").font(.caption) }
            }
            Section("4. Track an issue") {
                Text("GitHub CLI must be installed and authenticated. Run gh auth login in Terminal if access fails.").font(.caption)
                TextField("https://github.com/owner/repository/issues/123", text: $issueURL)
                    .disabled(setup.busy)
                    .onChange(of: issueURL) { _ in setup.preview = nil }
                Button(setup.busy ? "Checking…" : "Preview issue checklist") { Task { await setup.load(issueURL) } }
                    .disabled(setup.busy || issueURL.isEmpty)
                if let preview = setup.preview {
                    Text(preview.title).font(.headline)
                    ForEach(preview.todos) { todo in Text("\(todo.id): \(todo.description)").font(.caption) }
                    Button("Import \(preview.todos.count) tasks") { Task { await setup.importPreview(into: model.store); model.refresh() } }
                        .disabled(setup.busy || model.store == nil)
                }
                if let result = setup.result { Text(result).font(.caption).textSelection(.enabled) }
                Text("Checklist example: - [ ] **TT-01 — Implement the change.** Check: the result works.")
                    .font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                Text("Importing does not launch an agent. MCP exposes reporting tools; your agent must use them. Session-file watching is optional. Local updates do not automatically write to GitHub.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped)
    }
    private var aboutPane: some View {
        Form {
            Section("Application") {
                LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Development")
                Text(Bundle.main.bundlePath).font(.caption).textSelection(.enabled)
                Text("Local build; unsigned and unnotarized.").font(.caption)
            }
            Section("Local data and health") {
                Text(storeURL.path).font(.caption).textSelection(.enabled)
                Button("Open Data Folder") { NSWorkspace.shared.open(storeURL.deletingLastPathComponent()) }
                LabeledContent("Last refresh", value: model.lastRefreshAt?.formatted() ?? "Not yet")
                ForEach(Array(Set([model.error, model.githubError, model.watcherError, notifications.lastError].compactMap { $0 })).sorted(), id: \.self) { Text($0).font(.caption).foregroundStyle(.red) }
                Button("Copy basic diagnostics") {
                    copy("Tracker Trapper \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "development")\nmacOS \(ProcessInfo.processInfo.operatingSystemVersionString)\nPermission: \(notifications.statusText)\nPresentation: \(notifications.alertText)\nApp sound preference: \(sound)\nLast refresh: \(model.lastRefreshAt?.formatted() ?? "not yet")\nVisible plans: \(model.snapshot.plans.count)\nSession watches: \(model.watches.count)")
                }
                Text("Copied diagnostics exclude file paths, issue text, credentials, and session transcripts.").font(.caption)
            }
        }.formStyle(.grouped)
    }
    private func copy(_ text: String) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string) }
}
