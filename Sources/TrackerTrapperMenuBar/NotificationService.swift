import AppKit
import Combine
import UserNotifications

enum NoticeKind { case completion, attention, stale, test }

struct NotificationPreferences {
    let defaults: UserDefaults
    func enabled(_ key: String) -> Bool { defaults.object(forKey: key) as? Bool ?? true }
    var sound: Bool { enabled("notifications.sound") }
    func allows(_ kind: NoticeKind) -> Bool {
        guard enabled("notifications.enabled") else { return false }
        switch kind {
        case .completion: return enabled("notifications.completions")
        case .attention: return enabled("notifications.attention")
        case .stale: return enabled("notifications.stale")
        case .test: return true
        }
    }
}

struct NotificationSystemState: Sendable {
    var authorization: UNAuthorizationStatus
    var alerts: UNNotificationSetting
    var sounds: UNNotificationSetting
    var style: UNAlertStyle = .none
}

@MainActor protocol NotificationClient {
    func settings() async -> NotificationSystemState
    func authorize() async throws -> Bool
    func submit(title: String, subtitle: String, body: String, sound: Bool) async throws
}

@MainActor final class MacNotificationClient: NotificationClient {
    func settings() async -> NotificationSystemState {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return .init(authorization: settings.authorizationStatus, alerts: settings.alertSetting,
                     sounds: settings.soundSetting, style: settings.alertStyle)
    }
    func authorize() async throws -> Bool {
        try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
    }
    func submit(title: String, subtitle: String, body: String, sound: Bool) async throws {
        let content = UNMutableNotificationContent()
        content.title = title; content.subtitle = subtitle; content.body = body
        if sound { content.sound = .default }
        try await UNUserNotificationCenter.current().add(UNNotificationRequest(
            identifier: "tracker-trapper-\(UUID().uuidString)", content: content, trigger: nil))
    }
}

@MainActor final class NotificationService: ObservableObject {
    static let shared = NotificationService()
    let preferences: NotificationPreferences
    private let client: any NotificationClient
    @Published private(set) var state: NotificationSystemState?
    @Published private(set) var lastResult: String?
    @Published private(set) var lastAttempt: Date?
    @Published private(set) var lastError: String?
    @Published private(set) var isRequesting = false

    init(client: any NotificationClient = MacNotificationClient(), defaults: UserDefaults = .standard) {
        self.client = client; preferences = NotificationPreferences(defaults: defaults)
    }
    func refresh() async { state = await client.settings() }
    func requestPermission() async {
        guard !isRequesting else { return }
        isRequesting = true
        defer { isRequesting = false }
        do {
            let granted = try await client.authorize()
            lastError = nil
            lastResult = granted ? "Permission granted. Send a test notification to check presentation." : "Permission declined. Enable Tracker Trapper in macOS Notification Settings."
        } catch {
            lastError = "Permission request failed: \(error.localizedDescription)"; lastResult = lastError
        }
        await refresh()
    }
    func send(title: String, subtitle: String = "", body: String, kind: NoticeKind) async {
        // Read preferences on each attempt; toggling them never replays historical events.
        guard preferences.allows(kind) else {
            if kind == .test { lastResult = "Turn on notifications in Tracker Trapper before sending a test." }
            return
        }
        await refresh()
        lastAttempt = .now
        guard let state else { return }
        switch state.authorization {
        case .denied:
            lastError = "macOS blocks notifications. Open System Settings → Notifications → Tracker Trapper."
            lastResult = lastError; return
        case .notDetermined:
            lastResult = "Notification permission has not been requested. Choose Enable Notifications."
            lastError = nil; return
        case .authorized, .provisional, .ephemeral: break
        @unknown default:
            lastError = "Unknown macOS notification permission. Check System Settings."; lastResult = lastError; return
        }
        do {
            try await client.submit(title: title, subtitle: subtitle, body: body, sound: preferences.sound)
            lastError = nil
            lastResult = state.alerts == .disabled || state.style == .none
                ? "Submitted to macOS; banners are disabled. Check Notification Center and macOS Notification Settings."
                : "Submitted to macOS. Focus or screen-sharing settings may still hide the banner."
        } catch {
            lastError = "Notification submission failed: \(error.localizedDescription)"; lastResult = lastError
        }
    }
    func sendTest() async {
        await send(title: "Tracker Trapper test", body: "This is a test notification. Your tracked tasks have not changed.", kind: .test)
    }
    func openSystemSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings")!
        if !NSWorkspace.shared.open(url) {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
        }
        lastResult = "In System Settings, choose Notifications → Tracker Trapper. Enable notifications and choose a banner style."
    }
    var statusText: String {
        guard let state else { return "Checking…" }
        switch state.authorization {
        case .authorized: return "Allowed"
        case .provisional: return "Quiet delivery"
        case .ephemeral: return "Temporarily allowed"
        case .denied: return "Blocked by macOS"
        case .notDetermined: return "Not requested"
        @unknown default: return "Unknown"
        }
    }
    var alertText: String {
        guard let state else { return "Checking…" }
        guard state.alerts == .enabled else { return state.alerts == .disabled ? "Disabled" : "Not supported" }
        switch state.style { case .banner: return "Banners"; case .alert: return "Alerts"; default: return "None" }
    }
    var soundText: String {
        guard let state else { return "Checking…" }
        return state.sounds == .enabled ? "Enabled" : state.sounds == .disabled ? "Disabled" : "Not supported"
    }
}
