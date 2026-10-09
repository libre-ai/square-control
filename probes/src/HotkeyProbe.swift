// P2: RegisterEventHotKey for direct shortcuts, with no permission and no keyboard tap.
// usage: HotkeyProbe <output file> <seconds>   (launched by `open`, its own responsible process)

import AppKit
import ApplicationServices
import Carbon.HIToolbox

let arguments = CommandLine.arguments
guard arguments.count == 3, let seconds = Double(arguments[2]) else { exit(2) }
let outputPath = arguments[1]

struct Registration {
    let name: String
    let keyCode: Int
    let modifiers: Int
}

let registrations = [
    Registration(name: "H1_ctrl_shift_cmd_left", keyCode: kVK_LeftArrow, modifiers: controlKey | shiftKey | cmdKey),
    Registration(name: "H2_opt_shift_f19", keyCode: kVK_F19, modifiers: optionKey | shiftKey),
    Registration(name: "H3_opt_f19", keyCode: kVK_F19, modifiers: optionKey),
    Registration(name: "H4_ctrl_opt_f19", keyCode: kVK_F19, modifiers: controlKey | optionKey),
]

nonisolated(unsafe) var pressed = [Int](repeating: 0, count: registrations.count)
nonisolated(unsafe) var released = [Int](repeating: 0, count: registrations.count)
var lines = ["probe=P2 pid=\(getpid()) bundle=\(Bundle.main.bundleIdentifier ?? "-")",
             "preflight ax_trusted=\(AXIsProcessTrusted()) listen_event=\(CGPreflightListenEventAccess())"]

let application = NSApplication.shared
application.setActivationPolicy(.accessory)

var types = [
    EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
    EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
]
let install = InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
    guard let event else { return OSStatus(eventNotHandledErr) }
    var identifier = EventHotKeyID()
    GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                      MemoryLayout<EventHotKeyID>.size, nil, &identifier)
    let index = Int(identifier.id)
    guard index < pressed.count else { return OSStatus(eventNotHandledErr) }
    if GetEventKind(event) == UInt32(kEventHotKeyPressed) { pressed[index] += 1 } else { released[index] += 1 }
    return noErr
}, types.count, &types, nil, nil)
lines.append("install_event_handler status=\(install)")

for (index, registration) in registrations.enumerated() {
    var reference: EventHotKeyRef?
    let status = RegisterEventHotKey(
        UInt32(registration.keyCode), UInt32(registration.modifiers),
        EventHotKeyID(signature: 0x5343_5032, id: UInt32(index)), GetApplicationEventTarget(), 0, &reference)
    lines.append("register \(registration.name) status=\(status)")
}

DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
    for (index, registration) in registrations.enumerated() {
        lines.append("count \(registration.name) pressed=\(pressed[index]) released=\(released[index])")
    }
    let written = (try? (lines.joined(separator: "\n") + "\n").write(toFile: outputPath, atomically: true, encoding: .utf8)) != nil
    exit(written ? 0 : 1)
}
application.run()
