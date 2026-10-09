import SCCore

/// A window as the orchestrator sees it: an opaque session handle, never a title.
public struct TargetWindow: Sendable, Hashable {
    public let pid: Int32
    public let handle: UInt64

    public init(pid: Int32, handle: UInt64) {
        self.pid = pid
        self.handle = handle
    }
}

public enum WindowSystemError: Error, Sendable, Equatable {
    case notTrusted
    case noFrontmostApplication
    case noWindow
    /// The target app did not answer within the AX messaging timeout.
    case timeout
    case axFailure(Int32)
}

/// Everything the orchestrator needs from the platform. Implemented by the AX adapter and by
/// test fakes; every call may suspend, none runs on the main actor except screen reading.
public protocol WindowSystem: Sendable {
    func focusedWindow() async throws(WindowSystemError) -> TargetWindow
    func frame(of window: TargetWindow) async throws(WindowSystemError) -> FfiRect
    func screens() async -> [FfiScreen]
    func setFrame(_ frame: FfiRect, of window: TargetWindow) async throws(WindowSystemError)
}
