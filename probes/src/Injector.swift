// Stimulus injector for P1 and P2 (PROTOCOL.txt G4). Runs from the shell, host identity.
// usage: injector flags <delay seconds>   -- P1: 10 x left Option, 10 x left Control, 10 x F18
//        injector hotkeys <delay seconds> -- P2: 10 x each hotkey, then 10 x H1 with right Control

//        injector hotkeys2 <delay seconds> -- P2 amendment A1: modifiers posted as key events
// Every mode refuses to post unless the helper app is frontmost (owner's apps never receive
// a synthetic keystroke).

import AppKit
import CoreGraphics
import Foundation

let arguments = CommandLine.arguments
guard arguments.count == 3, let delay = Double(arguments[2]) else { exit(2) }
let helperBundle = "org.libre-ai.square-control.helper"

func helperIsFrontmost() -> Bool {
    RunLoop.current.run(until: Date().addingTimeInterval(0.005))
    return NSWorkspace.shared.frontmostApplication?.bundleIdentifier == helperBundle
}

nonisolated(unsafe) var useKeyEventsForModifiers = false
guard let source = CGEventSource(stateID: .hidSystemState) else { exit(3) }
nonisolated(unsafe) var posted = 0

// Virtual key codes (HIToolbox Events.h) and NX device-dependent side bits (IOLLEvent.h).
let leftOption: CGKeyCode = 58, leftControl: CGKeyCode = 59, rightControl: CGKeyCode = 62
let leftShift: CGKeyCode = 56, leftCommand: CGKeyCode = 55
let leftArrow: CGKeyCode = 123, f18: CGKeyCode = 79, f19: CGKeyCode = 80
let deviceLeftControl: UInt64 = 0x01, deviceLeftShift: UInt64 = 0x02, deviceLeftCommand: UInt64 = 0x08
let deviceLeftOption: UInt64 = 0x20, deviceRightControl: UInt64 = 0x2000

func settle() { usleep(30_000) }

func post(_ event: CGEvent?) {
    guard let event else { return }
    event.post(tap: .cghidEventTap)
    posted += 1
    settle()
}

/// A modifier transition as the hardware produces it: a flagsChanged event carrying the
/// device-independent mask plus the side bit.
func modifier(_ key: CGKeyCode, flags: CGEventFlags, down: Bool = true) {
    // Amendment A1: a modifier posted as a plain key event (key down / key up of its virtual
    // key code) lets the HID system update its modifier state, which hotkey matching reads.
    let event = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: useKeyEventsForModifiers ? down : true)
    if !useKeyEventsForModifiers { event?.type = .flagsChanged }
    event?.flags = flags
    post(event)
}

func key(_ code: CGKeyCode, flags: CGEventFlags) {
    let down = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: true)
    down?.flags = flags
    post(down)
    let up = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: false)
    up?.flags = flags
    post(up)
}

struct Held {
    let key: CGKeyCode
    let flag: CGEventFlags
    let side: UInt64
}

/// Presses the modifiers one by one, the key, then releases the modifiers in reverse order.
func chord(_ held: [Held], _ code: CGKeyCode) {
    guard helperIsFrontmost() else {
        print("injector stopped: helper app lost the front after \(posted) events")
        exit(4)
    }
    var flags = CGEventFlags(rawValue: 0)
    for modifierKey in held {
        flags.insert(modifierKey.flag)
        flags.insert(CGEventFlags(rawValue: modifierKey.side))
        modifier(modifierKey.key, flags: flags)
    }
    key(code, flags: flags)
    for modifierKey in held.reversed() {
        flags.remove(modifierKey.flag)
        flags.remove(CGEventFlags(rawValue: modifierKey.side))
        modifier(modifierKey.key, flags: flags, down: false)
    }
}

let control = Held(key: leftControl, flag: .maskControl, side: deviceLeftControl)
let rightControlHeld = Held(key: rightControl, flag: .maskControl, side: deviceRightControl)
let shift = Held(key: leftShift, flag: .maskShift, side: deviceLeftShift)
let command = Held(key: leftCommand, flag: .maskCommand, side: deviceLeftCommand)
let option = Held(key: leftOption, flag: .maskAlternate, side: deviceLeftOption)

Thread.sleep(forTimeInterval: delay)
guard helperIsFrontmost() else {
    print("injector refused: helper app is not frontmost (\(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "-"))")
    exit(4)
}
var mode = arguments[1]
if mode == "hotkeys2" {
    useKeyEventsForModifiers = true
    mode = "hotkeys"
}
switch mode {
case "flags":
    for _ in 0..<10 {
        modifier(leftOption, flags: [.maskAlternate, CGEventFlags(rawValue: deviceLeftOption)])
        modifier(leftOption, flags: [])
    }
    for _ in 0..<10 {
        modifier(leftControl, flags: [.maskControl, CGEventFlags(rawValue: deviceLeftControl)])
        modifier(leftControl, flags: [])
    }
    for _ in 0..<10 { key(f18, flags: []) }
case "hotkeys":
    for _ in 0..<10 { chord([control, shift, command], leftArrow) }   // H1
    for _ in 0..<10 { chord([option, shift], f19) }                   // H2
    for _ in 0..<10 { chord([option], f19) }                          // H3
    for _ in 0..<10 { chord([control, option], f19) }                 // H4
    for _ in 0..<10 { chord([rightControlHeld, shift, command], leftArrow) } // H1, right Control
default:
    exit(2)
}
print("injector mode=\(arguments[1]) events_posted=\(posted)")
