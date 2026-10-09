import CoreGraphics
import Foundation
let flags: CGEventFlags = [.maskControl, .maskAlternate, .maskCommand]
for (label, tap, state) in [("hid/hidSystem", CGEventTapLocation.cghidEventTap, CGEventSourceStateID.hidSystemState),
                            ("session/combined", .cgSessionEventTap, .combinedSessionState),
                            ("annotated/private", .cgAnnotatedSessionEventTap, .privateState)] {
  let src = CGEventSource(stateID: state)
  let d = CGEvent(keyboardEventSource: src, virtualKey: 38, keyDown: true); d?.flags = flags; d?.post(tap: tap)
  usleep(50000)
  let u = CGEvent(keyboardEventSource: src, virtualKey: 38, keyDown: false); u?.flags = flags; u?.post(tap: tap)
  print("posted \(label)"); usleep(800000)
}
