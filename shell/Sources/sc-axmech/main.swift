// P3 probe: AX mechanics through the product's own AX gateway and executor.
// usage: sc-axmech move <pid> <repetitions>
//        sc-axmech frozen <frozen pid> <responsive pid> <repetitions>
// Run from the shell it carries the host's identity (PROTOCOL.txt G2): it measures AX
// mechanics, never permissions. It only touches windows the probe run opened (G6).

import Darwin
import Foundation
import SCCore
import SquareControlKit

func text(_ rect: FfiRect) -> String { "\(rect.x),\(rect.y),\(rect.width),\(rect.height)" }

func microseconds(since start: ContinuousClock.Instant) -> Int {
    let elapsed = ContinuousClock.now - start
    return Int(elapsed.components.seconds * 1_000_000 + elapsed.components.attoseconds / 1_000_000_000_000)
}

/// Reads until 3 identical consecutive frames 1 ms apart (max 50 reads), as the bench does.
func stableFrame(_ system: AXWindowSystem, _ window: TargetWindow) async throws(WindowSystemError) -> (FfiRect, Int) {
    var previous: FfiRect?
    var identical = 0
    for read in 1...50 {
        let frame = try await system.frame(of: window)
        identical = frame == previous ? identical + 1 : 1
        previous = frame
        if identical == 3, let frame = previous { return (frame, read) }
        try? await Task.sleep(for: .milliseconds(1))
    }
    guard let previous else { throw .noWindow }
    return (previous, 50)
}

@MainActor
func leftHalfPlan(for frame: FfiRect) throws -> FfiRect {
    try resolve(action: .leftHalf, snapshot: FfiSnapshot(window: frame, screens: currentScreens())).frame
}

// The scenarios run on the main actor on purpose: every AX call hops to the executor's queues,
// so the heartbeat measures whether the main actor is ever blocked by them.
@MainActor
func move(pid: Int32, repetitions: Int) async {
    let system = AXWindowSystem()
    do {
        let window = try await system.window(ofProcess: pid)
        let enhanced = try await system.enhancedUserInterface(of: window)
        let (initial, reads) = try await stableFrame(system, window)
        let plan = try leftHalfPlan(for: initial)
        print("target pid=\(pid) enhanced_ui=\(enhanced.map { "\($0)" } ?? "nil") initial=\(text(initial)) reads=\(reads) planned=\(text(plan))")
        var stable = 0
        for repetition in 1...repetitions {
            let start = ContinuousClock.now
            var error = "-"
            do { try await system.setFrame(plan, of: window) } catch let failure { error = "\(failure)" }
            let applyMicros = microseconds(since: start)
            let (obtained, obtainedReads) = try await stableFrame(system, window)
            if obtainedReads < 50 { stable += 1 }
            let deltas = [obtained.x - plan.x, obtained.y - plan.y, obtained.width - plan.width, obtained.height - plan.height]
            let restoreStart = ContinuousClock.now
            try await system.setFrame(initial, of: window)
            let restoreMicros = microseconds(since: restoreStart)
            let (restored, _) = try await stableFrame(system, window)
            print("rep=\(repetition) apply_us=\(applyMicros) error=\(error) obtained=\(text(obtained)) reads=\(obtainedReads) "
                + "delta=\(deltas.map { String($0) }.joined(separator: ",")) restore_us=\(restoreMicros) restored=\(text(restored))")
        }
        print("summary pid=\(pid) repetitions=\(repetitions) stable_readbacks=\(stable)")
    } catch {
        print("error pid=\(pid) \(error)")
    }
}

/// Main-actor heartbeat: the largest gap between 10 ms ticks while the frozen scenario runs.
@MainActor
final class Heartbeat {
    var maximumGapMicros = 0
    var running = true

    func start() {
        Task { @MainActor in
            var last = ContinuousClock.now
            while running {
                try? await Task.sleep(for: .milliseconds(10))
                maximumGapMicros = max(maximumGapMicros, microseconds(since: last))
                last = ContinuousClock.now
            }
        }
    }
}

@MainActor
func frozen(frozenPid: Int32, responsivePid: Int32, repetitions: Int) async {
    let system = AXWindowSystem()
    do {
        let frozenWindow = try await system.window(ofProcess: frozenPid)
        let responsiveWindow = try await system.window(ofProcess: responsivePid)
        let (initial, _) = try await stableFrame(system, responsiveWindow)
        let plan = try leftHalfPlan(for: initial)
        let heartbeat = Heartbeat()
        heartbeat.start()
        guard kill(frozenPid, SIGSTOP) == 0 else {
            print("error kill -STOP failed errno=\(errno)")
            return
        }
        print("frozen pid=\(frozenPid) responsive pid=\(responsivePid) timeout_s=\(AXExecutor.messagingTimeoutSeconds)")
        var bounded = 0
        var fastMoves = 0
        for repetition in 1...repetitions {
            let start = ContinuousClock.now
            async let frozenRead: (String, Int) = {
                let begin = ContinuousClock.now
                do {
                    let frame = try await system.frame(of: frozenWindow)
                    return ("ok \(text(frame))", microseconds(since: begin))
                } catch {
                    return ("\(error)", microseconds(since: begin))
                }
            }()
            async let responsiveMove: (String, Int) = {
                let begin = ContinuousClock.now
                let target = repetition.isMultiple(of: 2) ? initial : plan
                do {
                    try await system.setFrame(target, of: responsiveWindow)
                    return ("ok", microseconds(since: begin))
                } catch {
                    return ("\(error)", microseconds(since: begin))
                }
            }()
            let (frozenResult, frozenMicros) = await frozenRead
            let (moveResult, moveMicros) = await responsiveMove
            if frozenResult.hasPrefix("ok") == false, frozenMicros <= 300_000 { bounded += 1 }
            if moveResult == "ok", moveMicros <= 100_000 { fastMoves += 1 }
            print("rep=\(repetition) frozen_read=\(frozenResult) frozen_us=\(frozenMicros) responsive_move=\(moveResult) "
                + "move_us=\(moveMicros) wall_us=\(microseconds(since: start))")
        }
        kill(frozenPid, SIGCONT)
        try? await Task.sleep(for: .milliseconds(200))
        let after: String
        do { after = "ok \(text(try await system.frame(of: frozenWindow)))" } catch { after = "\(error)" }
        try? await system.setFrame(initial, of: responsiveWindow)
        heartbeat.running = false
        let gap = heartbeat.maximumGapMicros
        print("summary repetitions=\(repetitions) frozen_reads_bounded_300ms=\(bounded) responsive_moves_under_100ms=\(fastMoves) "
            + "main_actor_max_gap_us=\(gap) read_after_sigcont=\(after)")
    } catch {
        kill(frozenPid, SIGCONT)
        print("error \(error)")
    }
}

let arguments = CommandLine.arguments
switch (arguments.count, arguments.dropFirst().first) {
case (4, "move"):
    guard let pid = Int32(arguments[2]), let repetitions = Int(arguments[3]) else { exit(2) }
    await move(pid: pid, repetitions: repetitions)
case (5, "frozen"):
    guard let frozenPid = Int32(arguments[2]), let responsivePid = Int32(arguments[3]),
          let repetitions = Int(arguments[4]) else { exit(2) }
    await frozen(frozenPid: frozenPid, responsivePid: responsivePid, repetitions: repetitions)
default:
    print("usage: sc-axmech move <pid> <n> | frozen <frozen pid> <responsive pid> <n>")
    exit(2)
}
