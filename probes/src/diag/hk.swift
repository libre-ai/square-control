import AppKit
import Carbon.HIToolbox
nonisolated(unsafe) var calls = 0
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
var types = [EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))]
let s1 = InstallEventHandler(GetEventDispatcherTarget(), { _, _, _ in calls += 1; print("hotkey!"); return noErr }, 1, &types, nil, nil)
var ref: EventHotKeyRef?
let s2 = RegisterEventHotKey(UInt32(kVK_ANSI_J), UInt32(controlKey | optionKey | cmdKey), EventHotKeyID(signature: 1, id: 1), GetEventDispatcherTarget(), 0, &ref)
print("install=\(s1) register=\(s2)")
DispatchQueue.main.asyncAfter(deadline: .now() + 6) { print("calls=\(calls)"); exit(0) }
app.run()
