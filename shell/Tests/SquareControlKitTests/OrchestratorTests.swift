import SCCore
import Synchronization
import XCTest
@testable import SquareControlKit

/// Records every call and answers from a script, like the AX adapter would.
final class FakeWindowSystem: WindowSystem {
    struct Script: Sendable {
        var window = TargetWindow(pid: 42, handle: 7)
        var before = FfiRect(x: 300, y: 200, width: 800, height: 600)
        /// What the app accepts instead of the plan (an app with a size increment, say).
        var accepted = FfiRect(x: 0, y: 33, width: 750, height: 949)
        var screens = [FfiScreen(
            frame: FfiRect(x: 0, y: 0, width: 1512, height: 982),
            visible: FfiRect(x: 0, y: 33, width: 1512, height: 949))]
        var focusError: WindowSystemError?
    }

    let calls = Mutex<[String]>([])
    private let state: Mutex<(script: Script, applied: FfiRect?)>

    init(_ script: Script = Script()) {
        state = Mutex((script, nil))
    }

    func focusedWindow() async throws(WindowSystemError) -> TargetWindow {
        calls.withLock { $0.append("focusedWindow") }
        let script = state.withLock { $0.script }
        if let error = script.focusError { throw error }
        return script.window
    }

    func frame(of window: TargetWindow) async throws(WindowSystemError) -> FfiRect {
        calls.withLock { $0.append("frame") }
        return state.withLock { $0.applied == nil ? $0.script.before : $0.script.accepted }
    }

    func screens() async -> [FfiScreen] {
        calls.withLock { $0.append("screens") }
        return state.withLock { $0.script.screens }
    }

    func setFrame(_ frame: FfiRect, of window: TargetWindow) async throws(WindowSystemError) {
        calls.withLock { $0.append("setFrame \(frame.x),\(frame.y),\(frame.width),\(frame.height)") }
        state.withLock { $0.applied = frame }
    }
}

final class OrchestratorTests: XCTestCase {
    func testLeftHalfTraversesReadResolveApplyReadBackInOrder() async {
        let windows = FakeWindowSystem()
        let orchestrator = Orchestrator(windows: windows)
        let outcome = await orchestrator.perform(.leftHalf)
        XCTAssertEqual(
            windows.calls.withLock { $0 },
            ["focusedWindow", "frame", "screens", "setFrame 0.0,33.0,756.0,949.0", "frame"])
        XCTAssertEqual(outcome.planned, FfiRect(x: 0, y: 33, width: 756, height: 949))
        XCTAssertEqual(outcome.observed, FfiRect(x: 0, y: 33, width: 750, height: 949))
        XCTAssertNil(outcome.windowError)
    }

    func testHistoryRecordsTheObservedFramesNotThePlan() async {
        let orchestrator = Orchestrator(windows: FakeWindowSystem())
        _ = await orchestrator.perform(.leftHalf)
        let undo = await orchestrator.undoTarget(for: TargetWindow(pid: 42, handle: 7))
        XCTAssertEqual(undo, FfiRect(x: 300, y: 200, width: 800, height: 600))
    }

    func testAWindowSystemErrorStopsTheActionBeforeAnyWrite() async {
        var script = FakeWindowSystem.Script()
        script.focusError = .notTrusted
        let windows = FakeWindowSystem(script)
        let outcome = await Orchestrator(windows: windows).perform(.leftHalf)
        XCTAssertEqual(outcome.windowError, .notTrusted)
        XCTAssertEqual(windows.calls.withLock { $0 }, ["focusedWindow"])
    }

    func testNoScreenIsReportedAsAResolveErrorWithoutWriting() async {
        var script = FakeWindowSystem.Script()
        script.screens = []
        let windows = FakeWindowSystem(script)
        let outcome = await Orchestrator(windows: windows).perform(.leftHalf)
        XCTAssertEqual(outcome.resolveError, .NoScreen)
        XCTAssertFalse(windows.calls.withLock { $0 }.contains { $0.hasPrefix("setFrame") })
    }
}

/// Records the AX call order of the frame policy (FR-11).
final class RecordingOperations: FrameOperations {
    var log: [String] = []
    var enhanced: Bool?
    var failPosition = false

    func enhancedUserInterface() -> Bool? { log.append("getEnhanced"); return enhanced }
    func setEnhancedUserInterface(_ enabled: Bool) { log.append("setEnhanced \(enabled)") }
    func setSize(width: Double, height: Double) throws(WindowSystemError) { log.append("size \(width)x\(height)") }
    func setPosition(x: Double, y: Double) throws(WindowSystemError) {
        log.append("position \(x),\(y)")
        if failPosition { throw .timeout }
    }
}

final class FrameApplierTests: XCTestCase {
    private let frame = FfiRect(x: 0, y: 33, width: 756, height: 949)

    func testSizeThenPositionThenSize() throws {
        let operations = RecordingOperations()
        try applyFrame(frame, with: operations)
        XCTAssertEqual(operations.log, ["getEnhanced", "size 756.0x949.0", "position 0.0,33.0", "size 756.0x949.0"])
    }

    func testEnhancedUserInterfaceIsSwitchedOffAndRestored() throws {
        let operations = RecordingOperations()
        operations.enhanced = true
        try applyFrame(frame, with: operations)
        XCTAssertEqual(operations.log.first(where: { $0.hasPrefix("setEnhanced") }), "setEnhanced false")
        XCTAssertEqual(operations.log.last, "setEnhanced true")
    }

    func testEnhancedUserInterfaceIsRestoredEvenWhenAWriteFails() {
        let operations = RecordingOperations()
        operations.enhanced = true
        operations.failPosition = true
        XCTAssertThrowsError(try applyFrame(frame, with: operations))
        XCTAssertEqual(operations.log.last, "setEnhanced true")
    }
}
