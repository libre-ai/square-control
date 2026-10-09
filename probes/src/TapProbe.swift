// P1: does a modifier-only event tap (flagsChanged) need Input Monitoring on top of
// Accessibility? Run as an .app launched by `open` so that it is its own responsible process.
// usage: TapProbe <output file> <seconds>
// It never calls a prompting API (PROTOCOL.txt G3).

import ApplicationServices
import CoreGraphics
import Foundation

let arguments = CommandLine.arguments
guard arguments.count == 3, let seconds = Double(arguments[2]) else { exit(2) }
let outputPath = arguments[1]
var lines: [String] = []
@MainActor func emit(_ line: String) { lines.append(line) }

final class Counter {
    let name: String
    var flagsChanged = 0
    var keyDown = 0
    var keyUp = 0
    var disabledByTimeout = 0
    var disabledByUserInput = 0
    var leftOptionSideBit = 0
    var leftControlSideBit = 0
    var port: CFMachPort?
    init(name: String) { self.name = name }
}

// Device-dependent side bits of the NX flags (IOLLEvent.h).
let deviceLeftControl: UInt64 = 0x0000_0001
let deviceLeftOption: UInt64 = 0x0000_0020

let callback: CGEventTapCallBack = { _, type, event, userInfo in
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let counter = Unmanaged<Counter>.fromOpaque(userInfo).takeUnretainedValue()
    switch type {
    case .flagsChanged:
        counter.flagsChanged += 1
        let raw = event.flags.rawValue
        if raw & deviceLeftOption != 0 { counter.leftOptionSideBit += 1 }
        if raw & deviceLeftControl != 0 { counter.leftControlSideBit += 1 }
    case .keyDown: counter.keyDown += 1
    case .keyUp: counter.keyUp += 1
    case .tapDisabledByTimeout:
        counter.disabledByTimeout += 1
        if let port = counter.port { CGEvent.tapEnable(tap: port, enable: true) }
    case .tapDisabledByUserInput:
        counter.disabledByUserInput += 1
        if let port = counter.port { CGEvent.tapEnable(tap: port, enable: true) }
    default: break
    }
    return Unmanaged.passUnretained(event)
}

emit("probe=P1 pid=\(getpid()) bundle=\(Bundle.main.bundleIdentifier ?? "-")")
emit("preflight ax_trusted=\(AXIsProcessTrusted()) listen_event=\(CGPreflightListenEventAccess()) post_event=\(CGPreflightPostEventAccess())")

let flagsMask = CGEventMask(1 << CGEventType.flagsChanged.rawValue)
let keyMask = CGEventMask((1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue))
let specifications: [(String, CGEventTapOptions, CGEventMask)] = [
    ("A_listenOnly_flagsChanged", .listenOnly, flagsMask),
    ("B_defaultTap_flagsChanged", .defaultTap, flagsMask),
    ("C_listenOnly_keyDownUp", .listenOnly, keyMask),
]
var counters: [Counter] = []
for (name, options, mask) in specifications {
    let counter = Counter(name: name)
    let port = CGEvent.tapCreate(
        tap: .cgSessionEventTap, place: .headInsertEventTap, options: options, eventsOfInterest: mask,
        callback: callback, userInfo: Unmanaged.passUnretained(counter).toOpaque())
    counter.port = port
    emit("tap \(name) created=\(port != nil)")
    if let port {
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        emit("tap \(name) enabled=\(CGEvent.tapIsEnabled(tap: port))")
    }
    counters.append(counter)
}
emit("listening seconds=\(seconds)")
CFRunLoopRunInMode(.defaultMode, seconds, false)
for counter in counters {
    emit("count \(counter.name) flagsChanged=\(counter.flagsChanged) keyDown=\(counter.keyDown) keyUp=\(counter.keyUp) "
        + "left_option_bit=\(counter.leftOptionSideBit) left_control_bit=\(counter.leftControlSideBit) "
        + "disabled_timeout=\(counter.disabledByTimeout) disabled_user_input=\(counter.disabledByUserInput)")
}
emit("preflight_after ax_trusted=\(AXIsProcessTrusted()) listen_event=\(CGPreflightListenEventAccess())")
do {
    try (lines.joined(separator: "\n") + "\n").write(toFile: outputPath, atomically: true, encoding: .utf8)
} catch {
    exit(1)
}
