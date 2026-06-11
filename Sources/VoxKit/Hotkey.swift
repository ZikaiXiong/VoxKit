import Foundation
import AppKit
import Carbon

struct HotkeyPreset: Identifiable, Hashable {
    let id: String
    let label: String
    let keyCode: UInt32
    let modifiers: UInt32

    static let all: [HotkeyPreset] = [
        HotkeyPreset(id: "optSpace", label: "⌥ Space", keyCode: 49, modifiers: UInt32(optionKey)),
        HotkeyPreset(id: "ctrlOptSpace", label: "⌃⌥ Space", keyCode: 49, modifiers: UInt32(controlKey | optionKey)),
        HotkeyPreset(id: "cmdShiftSpace", label: "⌘⇧ Space", keyCode: 49, modifiers: UInt32(cmdKey | shiftKey)),
        HotkeyPreset(id: "ctrlGrave", label: "⌃ `", keyCode: 50, modifiers: UInt32(controlKey)),
    ]

    static func current() -> HotkeyPreset {
        let id = UserDefaults.standard.string(forKey: "hotkey") ?? "optSpace"
        return all.first { $0.id == id } ?? all[0]
    }
}

/// Global hotkey (Carbon RegisterEventHotKey, no Accessibility permission needed)
final class HotKeyManager {
    static let shared = HotKeyManager()

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    var onHotKey: (() -> Void)?

    func applyFromDefaults() {
        let preset = HotkeyPreset.current()
        register(keyCode: preset.keyCode, modifiers: preset.modifiers)
    }

    func register(keyCode: UInt32, modifiers: UInt32) {
        unregister()

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData -> OSStatus in
            guard let userData else { return noErr }
            let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async { manager.onHotKey?() }
            return noErr
        }, 1, &eventType, selfPtr, &handlerRef)

        let hotKeyID = EventHotKeyID(signature: OSType(0x564F584E), id: 1)   // 'VOXN'
        RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    func unregister() {
        if let ref = hotKeyRef { UnregisterEventHotKey(ref); hotKeyRef = nil }
        if let ref = handlerRef { RemoveEventHandler(ref); handlerRef = nil }
    }
}

/// Auto-paste into the frontmost app after copying (optional, requires Accessibility permission)
enum Paster {
    static var trusted: Bool { AXIsProcessTrusted() }

    static func requestTrust() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    static func pasteToFrontApp() {
        guard AXIsProcessTrusted() else { return }
        let source = CGEventSource(stateID: .combinedSessionState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true)   // V
        down?.flags = .maskCommand
        let up = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}
