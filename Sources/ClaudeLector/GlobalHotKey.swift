import Carbon
import Foundation

/// A system-wide shortcut (default ⌥⌘L) via Carbon's RegisterEventHotKey.
/// Needs no Accessibility permission.
@MainActor
final class GlobalHotKey {
    private var ref: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    nonisolated(unsafe) private static var action: (@MainActor () -> Void)?

    init(keyCode: Int = kVK_ANSI_L, modifiers: Int = cmdKey | optionKey, action: @escaping @MainActor () -> Void) {
        Self.action = action
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { GlobalHotKey.action?() } }
            return noErr
        }, 1, &spec, nil, &handlerRef)
        let id = EventHotKeyID(signature: OSType(0x4C_45_43_54), id: 1) // "LECT"
        RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), id, GetApplicationEventTarget(), 0, &ref)
    }
}
