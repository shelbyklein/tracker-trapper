import XCTest
import UserNotifications
@testable import TrackerTrapperMenuBar

@MainActor final class FakeNotifications: NotificationClient {
    var state = NotificationSystemState(authorization: .authorized, alerts: .enabled, sounds: .enabled, style: .banner)
    var submissionError: Error?
    var permissionError: Error?
    var authorizationResult = true
    var submissions: [(title: String, subtitle: String, body: String, sound: Bool)] = []
    func settings() async -> NotificationSystemState { state }
    func authorize() async throws -> Bool {
        if let permissionError { throw permissionError }
        state.authorization = authorizationResult ? .authorized : .denied
        return authorizationResult
    }
    func submit(title: String, subtitle: String, body: String, sound: Bool) async throws {
        if let submissionError { throw submissionError }
        submissions.append((title, subtitle, body, sound))
    }
}

final class NotificationServiceTests: XCTestCase {
    @MainActor func testAuthorizedNotificationForwardsCompletePayload() async {
        let name = "tt-tests-\(UUID())"; let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let client = FakeNotifications(); let service = NotificationService(client: client, defaults: defaults)

        await service.send(title: "Tracker Trapper", subtitle: "repo #12", body: "Build completed", kind: .completion)

        XCTAssertEqual(client.submissions.count, 1)
        XCTAssertEqual(client.submissions.first?.title, "Tracker Trapper")
        XCTAssertEqual(client.submissions.first?.subtitle, "repo #12")
        XCTAssertEqual(client.submissions.first?.body, "Build completed")
        XCTAssertEqual(client.submissions.first?.sound, true)
        XCTAssertNil(service.lastError)
        XCTAssertNotNil(service.lastAttempt)
        XCTAssertTrue(service.lastResult?.contains("Submitted to macOS") == true)
    }

    @MainActor func testTestAndRealNoticesRespectSoundAndMasterSwitch() async {
        let name = "tt-tests-\(UUID())"; let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let client = FakeNotifications(); let service = NotificationService(client: client, defaults: defaults)
        defaults.set(false, forKey: "notifications.sound")
        await service.sendTest()
        await service.send(title: "Todo completed", body: "Task", kind: .completion)
        XCTAssertEqual(client.submissions.count, 2)
        XCTAssertTrue(client.submissions.allSatisfy { !$0.sound })
        defaults.set(false, forKey: "notifications.enabled")
        await service.sendTest()
        await service.send(title: "Attention", body: "Blocked", kind: .attention)
        XCTAssertEqual(client.submissions.count, 2)
        XCTAssertTrue(service.lastResult?.contains("Turn on") == true)
    }

    @MainActor func testEventPreferencesAndPersistence() async {
        let name = "tt-tests-\(UUID())"; let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(false, forKey: "notifications.completions")
        defaults.set(false, forKey: "notifications.stale")
        let client = FakeNotifications()
        let service = NotificationService(client: client, defaults: UserDefaults(suiteName: name)!)
        await service.send(title: "Done", body: "Task", kind: .completion)
        await service.send(title: "Stale", body: "Run", kind: .stale)
        await service.send(title: "Blocked", body: "Task", kind: .attention)
        XCTAssertEqual(client.submissions.map(\.title), ["Blocked"])
    }

    @MainActor func testDeniedUndeterminedAndPermissionFailureAreVisible() async {
        let name = "tt-tests-\(UUID())"; let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let client = FakeNotifications(); let service = NotificationService(client: client, defaults: defaults)
        client.state.authorization = .denied
        await service.sendTest()
        XCTAssertNotNil(service.lastError)
        XCTAssertEqual(service.statusText, "Blocked by macOS")
        client.state.authorization = .notDetermined
        await service.sendTest()
        XCTAssertTrue(service.lastResult?.contains("Enable Notifications") == true)
        XCTAssertTrue(client.submissions.isEmpty)
        client.permissionError = NSError(domain: "test", code: 1)
        await service.requestPermission()
        XCTAssertTrue(service.lastError?.contains("Permission request failed") == true)
        XCTAssertFalse(service.isRequesting)
        client.permissionError = nil
        await service.requestPermission()
        XCTAssertEqual(service.statusText, "Allowed")
        XCTAssertNil(service.lastError)
    }

    @MainActor func testDeclinedPermissionAndSystemStateDescriptionsAreVisible() async {
        let name = "tt-tests-\(UUID())"; let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let client = FakeNotifications(); let service = NotificationService(client: client, defaults: defaults)
        client.authorizationResult = false

        await service.requestPermission()

        XCTAssertEqual(service.statusText, "Blocked by macOS")
        XCTAssertTrue(service.lastResult?.contains("Permission declined") == true)
        XCTAssertNil(service.lastError)
        XCTAssertFalse(service.isRequesting)

        client.state.authorization = .provisional
        client.state.alerts = .enabled
        client.state.style = .alert
        client.state.sounds = .notSupported
        await service.refresh()
        XCTAssertEqual(service.statusText, "Quiet delivery")
        XCTAssertEqual(service.alertText, "Alerts")
        XCTAssertEqual(service.soundText, "Not supported")
    }

    @MainActor func testSubmissionFailureAndRecoveryAndDisabledBanners() async {
        let name = "tt-tests-\(UUID())"; let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let client = FakeNotifications(); let service = NotificationService(client: client, defaults: defaults)
        client.submissionError = NSError(domain: "test", code: 2)
        await service.sendTest()
        XCTAssertTrue(service.lastError?.contains("submission failed") == true)
        XCTAssertNotNil(service.lastAttempt)
        client.submissionError = nil; client.state.alerts = .disabled; client.state.sounds = .disabled
        await service.sendTest()
        XCTAssertNil(service.lastError)
        XCTAssertTrue(service.lastResult?.contains("banners are disabled") == true)
        XCTAssertEqual(service.alertText, "Disabled")
        XCTAssertEqual(service.soundText, "Disabled")
        client.state.authorization = .provisional
        await service.refresh()
        XCTAssertEqual(service.statusText, "Quiet delivery")
    }
}
