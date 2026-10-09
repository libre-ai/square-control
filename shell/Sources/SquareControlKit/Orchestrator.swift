import SCCore

/// Result of one action, kept as data so that tests and the E2E channel can inspect it.
public struct ActionOutcome: Sendable, Equatable {
    public var window: TargetWindow?
    public var before: FfiRect?
    public var planned: FfiRect?
    public var observed: FfiRect?
    public var windowError: WindowSystemError?
    public var resolveError: FfiResolveError?
}

/// Runs an action end to end, off the main actor (spec v2 section 7, A-B3):
/// requirements -> read -> resolve -> apply -> read back -> commit(observed).
public actor Orchestrator {
    private let windows: any WindowSystem
    private var history: [FfiHistoryEntry] = []

    public init(windows: any WindowSystem) {
        self.windows = windows
    }

    public func undoTarget(for window: TargetWindow) -> FfiRect? {
        SCCore.undoTarget(history: history, window: window.handle)
    }

    public func perform(_ action: FfiAction) async -> ActionOutcome {
        var outcome = ActionOutcome()
        let needs = requirements(action: action)
        do {
            guard needs.focusedWindowFrame else { return outcome }
            let window = try await windows.focusedWindow()
            outcome.window = window
            let before = try await windows.frame(of: window)
            outcome.before = before
            let screens = needs.screens ? await windows.screens() : []
            let plan: FfiPlan
            do {
                plan = try resolve(action: action, snapshot: FfiSnapshot(window: before, screens: screens))
            } catch let error as FfiResolveError {
                outcome.resolveError = error
                return outcome
            } catch {
                // Generated bindings declare untyped throws; the core only throws FfiResolveError.
                outcome.resolveError = .InvalidGeometry
                return outcome
            }
            outcome.planned = plan.frame
            try await windows.setFrame(plan.frame, of: window)
            // The Plan is not the state: history records what the app actually accepted.
            let observed = try await windows.frame(of: window)
            outcome.observed = observed
            history = commit(
                history: history,
                observation: FfiObservation(window: window.handle, before: before, after: observed)
            )
        } catch {
            outcome.windowError = error
        }
        return outcome
    }
}
