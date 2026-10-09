import AppKit
import ApplicationServices
import Synchronization
import SCCore

/// AXUIElement is an immutable CF reference; every call on it is serialised on the queue of
/// its process, which is what makes sharing the reference across threads sound here.
struct UncheckedElement: @unchecked Sendable {
    let raw: AXUIElement
}

/// Runs AX calls off the main actor, one serial queue per process, with a bounded messaging
/// timeout: a frozen app blocks only its own queue, never the product or another app (A-B3).
public final class AXExecutor: Sendable {
    public static let messagingTimeoutSeconds: Float = 0.25
    private let queues = Mutex<[Int32: DispatchQueue]>([:])

    public init() {}

    private func queue(for pid: Int32) -> DispatchQueue {
        queues.withLock { queues in
            if let queue = queues[pid] { return queue }
            let queue = DispatchQueue(label: "org.libre-ai.square-control.ax.\(pid)", qos: .userInteractive)
            queues[pid] = queue
            return queue
        }
    }

    public func run<T: Sendable>(
        pid: Int32,
        _ body: @escaping @Sendable () throws(WindowSystemError) -> T
    ) async throws(WindowSystemError) -> T {
        let queue = queue(for: pid)
        let result: Result<T, WindowSystemError> = await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: Result { () throws(WindowSystemError) -> T in try body() })
            }
        }
        return try result.get()
    }
}

func mapAXError(_ error: AXError) -> WindowSystemError {
    switch error {
    case .apiDisabled: .notTrusted
    case .cannotComplete: .timeout
    case .noValue, .attributeUnsupported, .invalidUIElement: .noWindow
    default: .axFailure(error.rawValue)
    }
}

func copyAttribute(_ element: AXUIElement, _ name: String) throws(WindowSystemError) -> CFTypeRef {
    var value: CFTypeRef?
    let status = AXUIElementCopyAttributeValue(element, name as CFString, &value)
    guard status == .success, let value else { throw mapAXError(status == .success ? .noValue : status) }
    return value
}

func readFrame(_ window: AXUIElement) throws(WindowSystemError) -> FfiRect {
    let position = try copyAttribute(window, kAXPositionAttribute)
    let size = try copyAttribute(window, kAXSizeAttribute)
    var point = CGPoint.zero
    var extent = CGSize.zero
    // swiftlint:disable:next force_cast -- AX guarantees AXValue for these two attributes
    guard CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID(),
          AXValueGetValue(position as! AXValue, .cgPoint, &point),
          AXValueGetValue(size as! AXValue, .cgSize, &extent)
    else { throw .axFailure(AXError.illegalArgument.rawValue) }
    return FfiRect(x: point.x, y: point.y, width: extent.width, height: extent.height)
}

struct LiveFrameOperations: FrameOperations {
    let application: AXUIElement
    let window: AXUIElement

    func enhancedUserInterface() -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(application, "AXEnhancedUserInterface" as CFString, &value) == .success
        else { return nil }
        return (value as? Bool)
    }

    func setEnhancedUserInterface(_ enabled: Bool) {
        // Best effort: an app that refuses keeps its own setting, the frame call still runs.
        _ = AXUIElementSetAttributeValue(
            application, "AXEnhancedUserInterface" as CFString, enabled ? kCFBooleanTrue : kCFBooleanFalse)
    }

    func setSize(width: Double, height: Double) throws(WindowSystemError) {
        var size = CGSize(width: width, height: height)
        guard let value = AXValueCreate(.cgSize, &size) else { throw .axFailure(AXError.failure.rawValue) }
        let status = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, value)
        guard status == .success else { throw mapAXError(status) }
    }

    func setPosition(x: Double, y: Double) throws(WindowSystemError) {
        var point = CGPoint(x: x, y: y)
        guard let value = AXValueCreate(.cgPoint, &point) else { throw .axFailure(AXError.failure.rawValue) }
        let status = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, value)
        guard status == .success else { throw mapAXError(status) }
    }
}

/// Converts AppKit screens (bottom-left origin) into the core's space (top-left origin,
/// global points, index 0 = the screen with the menu bar).
@MainActor
public func currentScreens() -> [FfiScreen] {
    let screens = NSScreen.screens
    guard let primaryHeight = screens.first?.frame.height else { return [] }
    func flip(_ rect: NSRect) -> FfiRect {
        FfiRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }
    return screens.map { FfiScreen(frame: flip($0.frame), visible: flip($0.visibleFrame)) }
}

/// The only AX gateway of the product (NFR-S2): position, size, focused window, windows,
/// enhanced user interface. No title, value or document attribute is ever read.
public final class AXWindowSystem: WindowSystem {
    private struct Entry {
        let handle: UInt64
        let pid: Int32
        let application: UncheckedElement
        let window: UncheckedElement
    }

    private struct Table {
        var next: UInt64 = 1
        var entries: [Entry] = []
    }

    private static let tableBound = 500
    private let executor: AXExecutor
    private let table = Mutex(Table())

    public init(executor: AXExecutor = AXExecutor()) {
        self.executor = executor
    }

    private func entry(for window: TargetWindow) throws(WindowSystemError) -> Entry {
        guard let entry = table.withLock({ $0.entries.first { $0.handle == window.handle } }) else {
            throw .noWindow
        }
        return entry
    }

    public func focusedWindow() async throws(WindowSystemError) -> TargetWindow {
        guard AXIsProcessTrusted() else { throw .notTrusted }
        let pid = await MainActor.run { NSWorkspace.shared.frontmostApplication?.processIdentifier }
        guard let pid else { throw .noFrontmostApplication }
        let elements = try await executor.run(pid: pid) { () throws(WindowSystemError) -> (UncheckedElement, UncheckedElement) in
            let application = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(application, AXExecutor.messagingTimeoutSeconds)
            let window: AXUIElement
            if let focused = try? copyAttribute(application, kAXFocusedWindowAttribute),
               CFGetTypeID(focused) == AXUIElementGetTypeID() {
                window = focused as! AXUIElement // swiftlint:disable:this force_cast -- type id checked above
            } else if let windows = try? copyAttribute(application, kAXWindowsAttribute) as? [AXUIElement],
                      let first = windows.first {
                window = first
            } else {
                throw .noWindow
            }
            AXUIElementSetMessagingTimeout(window, AXExecutor.messagingTimeoutSeconds)
            return (UncheckedElement(raw: application), UncheckedElement(raw: window))
        }
        let handle = table.withLock { table -> UInt64 in
            // Same window seen again keeps its handle (identity by CFEqual, spec v2 section 7.1).
            if let known = table.entries.first(where: { CFEqual($0.window.raw, elements.1.raw) }) {
                return known.handle
            }
            let handle = table.next
            table.next += 1
            table.entries.append(Entry(handle: handle, pid: pid, application: elements.0, window: elements.1))
            if table.entries.count > Self.tableBound { table.entries.removeFirst() }
            return handle
        }
        return TargetWindow(pid: pid, handle: handle)
    }

    public func frame(of window: TargetWindow) async throws(WindowSystemError) -> FfiRect {
        let entry = try entry(for: window)
        let element = entry.window
        return try await executor.run(pid: entry.pid) { () throws(WindowSystemError) -> FfiRect in
            try readFrame(element.raw)
        }
    }

    public func screens() async -> [FfiScreen] {
        await MainActor.run { currentScreens() }
    }

    public func setFrame(_ frame: FfiRect, of window: TargetWindow) async throws(WindowSystemError) {
        let entry = try entry(for: window)
        let application = entry.application
        let element = entry.window
        try await executor.run(pid: entry.pid) { () throws(WindowSystemError) in
            try applyFrame(frame, with: LiveFrameOperations(application: application.raw, window: element.raw))
        }
    }
}
