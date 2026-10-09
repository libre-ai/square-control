// Helper app ("app d'aide" of the spec bench): one resizable window, records every key event
// it receives, and reports its pid. It is the AX target of P3 and the leak detector of P2.
// usage: SCHelper <output file> <seconds>

import AppKit

let arguments = CommandLine.arguments
guard arguments.count == 3, let seconds = Double(arguments[2]) else { exit(2) }
let outputPath = arguments[1]

nonisolated(unsafe) var keyEvents: [String: Int] = [:]

let application = NSApplication.shared
application.setActivationPolicy(.regular)

let window = NSWindow(
    contentRect: NSRect(x: 200, y: 200, width: 640, height: 420),
    styleMask: [.titled, .resizable, .miniaturizable, .closable], backing: .buffered, defer: false)
window.title = "SC Helper"
window.makeKeyAndOrderFront(nil)

NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { event in
    let name = "\(event.type == .keyDown ? "keyDown" : "keyUp") keyCode=\(event.keyCode)"
    keyEvents[name, default: 0] += 1
    return event
}

func flush(final: Bool) {
    var lines = ["helper pid=\(getpid()) final=\(final)"]
    lines += keyEvents.sorted { $0.key < $1.key }.map { "received \($0.key) n=\($0.value)" }
    lines.append("received_total=\(keyEvents.values.reduce(0, +))")
    try? (lines.joined(separator: "\n") + "\n").write(toFile: outputPath, atomically: true, encoding: .utf8)
}

flush(final: false)
application.activate()
DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
    flush(final: true)
    exit(0)
}
application.run()
