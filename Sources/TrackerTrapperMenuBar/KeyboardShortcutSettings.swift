import AppKit
import Carbon.HIToolbox
import SwiftUI

struct KeyboardShortcut: Codable, Equatable, Sendable {
    var keyCode: UInt32
    var modifiers: UInt32

    static let defaultShortcut = KeyboardShortcut(keyCode: UInt32(kVK_ANSI_T), modifiers: UInt32(cmdKey | shiftKey))

    var displayName: String {
        let symbols = [
            (UInt32(cmdKey), "⌘"),
            (UInt32(shiftKey), "⇧"),
            (UInt32(optionKey), "⌥"),
            (UInt32(controlKey), "⌃")
        ].compactMap { modifiers & $0.0 == 0 ? nil : $0.1 }.joined()
        return symbols + Self.keyName(keyCode)
    }

    init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var carbon: UInt32 = 0
        if flags.contains(.command) { carbon |= UInt32(cmdKey) }
        if flags.contains(.shift) { carbon |= UInt32(shiftKey) }
        if flags.contains(.option) { carbon |= UInt32(optionKey) }
        if flags.contains(.control) { carbon |= UInt32(controlKey) }
        guard carbon & UInt32(cmdKey | optionKey | controlKey) != 0 else { return nil }
        self.init(keyCode: UInt32(event.keyCode), modifiers: carbon)
    }

    private static func keyName(_ keyCode: UInt32) -> String {
        let special: [UInt32: String] = [
            UInt32(kVK_Space): "Space", UInt32(kVK_Return): "↩", UInt32(kVK_Tab): "⇥",
            UInt32(kVK_Delete): "⌫", UInt32(kVK_ForwardDelete): "⌦", UInt32(kVK_Escape): "⎋",
            UInt32(kVK_LeftArrow): "←", UInt32(kVK_RightArrow): "→",
            UInt32(kVK_UpArrow): "↑", UInt32(kVK_DownArrow): "↓",
            UInt32(kVK_F1): "F1", UInt32(kVK_F2): "F2", UInt32(kVK_F3): "F3", UInt32(kVK_F4): "F4",
            UInt32(kVK_F5): "F5", UInt32(kVK_F6): "F6", UInt32(kVK_F7): "F7", UInt32(kVK_F8): "F8",
            UInt32(kVK_F9): "F9", UInt32(kVK_F10): "F10", UInt32(kVK_F11): "F11", UInt32(kVK_F12): "F12"
        ]
        if let special = special[keyCode] { return special }
        let source = TISCopyCurrentKeyboardLayoutInputSource().takeRetainedValue()
        guard let raw = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return "Key (keyCode)" }
        let data = unsafeBitCast(raw, to: CFData.self)
        guard let bytes = CFDataGetBytePtr(data) else { return "Key (keyCode)" }
        let layout = UnsafeRawPointer(bytes).assumingMemoryBound(to: UCKeyboardLayout.self)
        var deadKeyState: UInt32 = 0
        var length = 0
        var characters = [UniChar](repeating: 0, count: 4)
        let result = UCKeyTranslate(layout, UInt16(keyCode), UInt16(kUCKeyActionDisplay), 0,
                                    UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysBit),
                                    &deadKeyState, characters.count, &length, &characters)
        guard result == noErr, length > 0 else { return "Key (keyCode)" }
        return String(utf16CodeUnits: characters, count: length).uppercased()
    }
}

@MainActor final class KeyboardShortcutSettings: ObservableObject {
    static let shared = KeyboardShortcutSettings()
    static let key = "keyboardShortcut"
    static let changed = Notification.Name("TrackerTrapperKeyboardShortcutChanged")

    @Published var shortcut: KeyboardShortcut {
        didSet {
            if let data = try? JSONEncoder().encode(shortcut) { defaults.set(data, forKey: Self.key) }
            registrationError = nil
            NotificationCenter.default.post(name: Self.changed, object: self)
        }
    }
    @Published var registrationError: String?
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.key), let saved = try? JSONDecoder().decode(KeyboardShortcut.self, from: data) {
            shortcut = saved
        } else {
            shortcut = .defaultShortcut
        }
    }

    func reset() { shortcut = .defaultShortcut }
}

struct KeyboardShortcutRecorder: NSViewRepresentable {
    @Binding var shortcut: KeyboardShortcut

    func makeNSView(context: Context) -> ShortcutRecorderButton {
        let button = ShortcutRecorderButton()
        button.onShortcut = { shortcut = $0 }
        button.shortcut = shortcut
        return button
    }

    func updateNSView(_ button: ShortcutRecorderButton, context: Context) {
        button.onShortcut = { shortcut = $0 }
        button.shortcut = shortcut
    }
}

final class ShortcutRecorderButton: NSButton {
    var onShortcut: ((KeyboardShortcut) -> Void)?
    var shortcut = KeyboardShortcut.defaultShortcut { didSet { if !recording { title = shortcut.displayName } } }
    private var recording = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        bezelStyle = .rounded
        setButtonType(.momentaryPushIn)
        target = self
        action = #selector(beginRecording)
        title = shortcut.displayName
        toolTip = "Click, then type a new keyboard shortcut"
        setAccessibilityLabel("Keyboard shortcut")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var acceptsFirstResponder: Bool { true }

    @objc private func beginRecording() {
        recording = true
        title = "Type shortcut…"
        window?.makeFirstResponder(self)
    }

    override func resignFirstResponder() -> Bool {
        recording = false
        title = shortcut.displayName
        return super.resignFirstResponder()
    }

    override func keyDown(with event: NSEvent) {
        guard recording else { return super.keyDown(with: event) }
        if event.keyCode == UInt16(kVK_Escape) {
            _ = resignFirstResponder()
            return
        }
        guard let value = KeyboardShortcut(event: event) else {
            NSSound.beep()
            title = "Include ⌘, ⌥, or ⌃"
            return
        }
        shortcut = value
        onShortcut?(value)
        _ = resignFirstResponder()
    }
}
