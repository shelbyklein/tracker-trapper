import AppKit
import SwiftUI
import XCTest
@testable import TrackerTrapperMenuBar

final class AppearanceSettingsTests: XCTestCase {
    @MainActor func testPreferencesPersistAndResetWithoutChangingOtherSettings() throws {
        let suite = "TrackerAppearanceTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(false, forKey: "notifications.enabled")
        let settings = AppearanceSettings(defaults: defaults)
        XCTAssertEqual(settings.preferences, GlassPreferences())
        settings.preferences.clarity = .frosted
        settings.preferences.tintStrength = 0.7
        settings.preferences.opacity = 0.4
        settings.color = Color(red: 0.8, green: 0.2, blue: 0.6)
        let reloaded = AppearanceSettings(defaults: defaults)
        XCTAssertEqual(reloaded.preferences, settings.preferences)
        XCTAssertEqual(reloaded.preferences.red, 0.8, accuracy: 0.01)
        reloaded.reset()
        XCTAssertEqual(AppearanceSettings(defaults: defaults).preferences, GlassPreferences())
        XCTAssertFalse(defaults.bool(forKey: "notifications.enabled"))
        defaults.set(Data("invalid".utf8), forKey: AppearanceSettings.key)
        XCTAssertEqual(AppearanceSettings(defaults: defaults).preferences, GlassPreferences())
    }

    @MainActor func testStoredValuesAreClamped() throws {
        let suite = "TrackerAppearanceTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var values = GlassPreferences()
        values.tintStrength = 8; values.opacity = -1; values.red = 4
        defaults.set(try JSONEncoder().encode(values), forKey: AppearanceSettings.key)
        let settings = AppearanceSettings(defaults: defaults)
        XCTAssertEqual(settings.preferences.tintStrength, 1)
        XCTAssertEqual(settings.preferences.opacity, 0)
        XCTAssertEqual(settings.preferences.red, 1)
    }

    @MainActor func testAppearancePaneRendersAtSettingsWindowSize() async throws {
        let suite = "TrackerAppearanceTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppearanceSettings(defaults: defaults)
        let host = NSHostingView(rootView: AppearancePane(appearance: settings).frame(width: 640, height: 540))
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 640, height: 540), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.title = "Appearance preview"
        window.contentView = host
        window.orderFrontRegardless()
        defer { window.orderOut(nil) }
        for clarity in GlassPreferences.Clarity.allCases {
            settings.preferences.clarity = clarity
            settings.preferences.tintStrength = clarity == .frosted ? 0.6 : 0.09
            try await Task.sleep(for: .milliseconds(250))
            host.layoutSubtreeIfNeeded()
            XCTAssertEqual(host.fittingSize.width, 640, accuracy: 1)
            XCTAssertEqual(host.fittingSize.height, 540, accuracy: 1)
            if let directory = ProcessInfo.processInfo.environment["TT_GLASS_REVIEW_DIR"] {
                let capture = Process()
                capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                capture.arguments = ["-x", "-l", String(window.windowNumber), "\(directory)/appearance-\(clarity.rawValue).png"]
                try capture.run(); capture.waitUntilExit()
                XCTAssertEqual(capture.terminationStatus, 0)
            }
        }
    }
}
