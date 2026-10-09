import AppKit
import ApplicationServices
import os
import SCCore
import SquareControlKit

private let logger = Logger(subsystem: "org.libre-ai.square-control", category: "app")

private func describe(_ rect: FfiRect?) -> String {
    guard let rect else { return "-" }
    return "\(rect.x),\(rect.y),\(rect.width),\(rect.height)"
}

private func describe(_ outcome: ActionOutcome) -> String {
    "before=\(describe(outcome.before)) planned=\(describe(outcome.planned)) observed=\(describe(outcome.observed)) "
        + "window_error=\(outcome.windowError.map { "\($0)" } ?? "-") resolve_error=\(outcome.resolveError.map { "\($0)" } ?? "-")"
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let orchestrator = Orchestrator(windows: AXWindowSystem())
    private let hotkeys = HotkeyCenter()
    private let state = StateFile.standard()
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let trusted = AXIsProcessTrusted()
        let dispatcher = hotkeys.start()
        let registration = hotkeys.register(.leftHalf) { [orchestrator] phase in
            guard phase == .pressed else { return }
            Task {
                let outcome = await orchestrator.perform(.leftHalf)
                logger.info("left_half \(describe(outcome), privacy: .private)")
            }
        }
        record("launch build=\(BuildInfo.stamp) commit=\(BuildInfo.commit) ax_trusted=\(trusted) "
            + "hotkey_dispatcher=\(dispatcher) hotkey_left_half=\(registration)")

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.title = "\u{25A3}"
        item.button?.setAccessibilityLabel(String(localized: "Square Control"))
        let menu = NSMenu()
        menu.addItem(withTitle: String(localized: "Quit Square Control"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        statusItem = item

        #if SC_E2E
        runEndToEndChannelIfRequested()
        #endif
    }

    private func record(_ line: String) {
        do {
            try state.append("\(Date().ISO8601Format()) \(line)")
        } catch {
            logger.error("state file write failed: \(String(describing: error), privacy: .public)")
        }
    }

    #if SC_E2E
    /// E2E channel, compiled only in the test configuration (AT-27): it performs one action on
    /// the frontmost window and records the outcome, then quits.
    private func runEndToEndChannelIfRequested() {
        guard CommandLine.arguments.contains("--sc-e2e-left-half") else { return }
        Task { [orchestrator] in
            try? await Task.sleep(for: .seconds(1))
            let outcome = await orchestrator.perform(.leftHalf)
            self.record("sc-e2e left_half \(describe(outcome))")
            NSApplication.shared.terminate(nil)
        }
    }
    #endif
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.setActivationPolicy(.accessory)
application.run()
