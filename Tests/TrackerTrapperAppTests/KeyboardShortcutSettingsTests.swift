import Carbon.HIToolbox
import XCTest
@testable import TrackerTrapperMenuBar

final class KeyboardShortcutSettingsTests: XCTestCase {
    @MainActor func testDefaultShortcutAndPersistence() throws {
        let suite = "shortcut-tests-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = KeyboardShortcutSettings(defaults: defaults)
        XCTAssertEqual(settings.shortcut, .defaultShortcut)
        XCTAssertEqual(settings.shortcut.displayName, "⌘⇧T")

        settings.shortcut = KeyboardShortcut(keyCode: UInt32(kVK_ANSI_K), modifiers: UInt32(controlKey | optionKey))
        let reloaded = KeyboardShortcutSettings(defaults: defaults)
        XCTAssertEqual(reloaded.shortcut, settings.shortcut)
        XCTAssertEqual(reloaded.shortcut.displayName, "⌥⌃K")

        reloaded.reset()
        XCTAssertEqual(reloaded.shortcut, .defaultShortcut)
    }

    @MainActor func testInvalidStoredShortcutFallsBackToDefault() throws {
        let suite = "shortcut-tests-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(Data("invalid".utf8), forKey: KeyboardShortcutSettings.key)
        XCTAssertEqual(KeyboardShortcutSettings(defaults: defaults).shortcut, .defaultShortcut)
    }
}
