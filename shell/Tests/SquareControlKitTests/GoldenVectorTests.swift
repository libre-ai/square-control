import Foundation
import SCCore
import XCTest

/// Same vectors as crates/layout/tests/golden.rs, through the real UniFFI bridge (NFR-Q1).
final class GoldenVectorTests: XCTestCase {
    private enum Expected {
        case plan(FfiRect, UInt32)
        case failure(FfiResolveError)
    }

    private struct Unreadable: Error, CustomStringConvertible {
        let description: String
    }

    private static let vectorsURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("golden/vectors.v1.txt")

    private func parse(_ line: String) throws -> (String, FfiAction, FfiSnapshot, Expected) {
        var tokens = line.split(separator: " ", omittingEmptySubsequences: false).map(String.init)[...]
        func next() throws -> String {
            guard let token = tokens.popFirst() else { throw Unreadable(description: "truncated: \(line)") }
            return token
        }
        func number() throws -> Double {
            let token = try next()
            guard let value = Double(token) else { throw Unreadable(description: "not a number \(token): \(line)") }
            return value
        }
        func rect() throws -> FfiRect {
            FfiRect(x: try number(), y: try number(), width: try number(), height: try number())
        }
        let id = try next()
        guard try next() == "left_half" else { throw Unreadable(description: "unknown action: \(line)") }
        let window = try rect()
        let count = Int(try number())
        var screens: [FfiScreen] = []
        for _ in 0..<count { screens.append(FfiScreen(frame: try rect(), visible: try rect())) }
        let expected: Expected
        switch try next() {
        case "ok": expected = .plan(try rect(), UInt32(try number()))
        case "err":
            switch try next() {
            case "NoScreen": expected = .failure(.NoScreen)
            case "InvalidGeometry": expected = .failure(.InvalidGeometry)
            default: throw Unreadable(description: "unknown error: \(line)")
            }
        default: throw Unreadable(description: "unknown expectation: \(line)")
        }
        guard tokens.isEmpty else { throw Unreadable(description: "trailing tokens: \(line)") }
        return (id, .leftHalf, FfiSnapshot(window: window, screens: screens), expected)
    }

    private func bits(_ rect: FfiRect) -> [UInt64] {
        [rect.x.bitPattern, rect.y.bitPattern, rect.width.bitPattern, rect.height.bitPattern]
    }

    func testGoldenVectorsHoldBitForBitThroughTheBridge() throws {
        let text = try String(contentsOf: Self.vectorsURL, encoding: .utf8)
        var executed = 0
        var failures: [String] = []
        for line in text.split(separator: "\n").map(String.init) where !line.isEmpty && !line.hasPrefix("#") {
            let (id, action, snapshot, expected) = try parse(line)
            executed += 1
            let actual = Result { try resolve(action: action, snapshot: snapshot) }
            switch (expected, actual) {
            case let (.plan(frame, index), .success(plan)) where bits(frame) == bits(plan.frame) && index == plan.screenIndex:
                break
            case let (.failure(error), .failure(actualError)) where (actualError as? FfiResolveError) == error:
                break
            default:
                failures.append("\(id): expected \(expected), got \(actual)")
            }
        }
        print("golden vectors executed through the bridge: \(executed), failed: \(failures.count)")
        XCTAssertGreaterThan(executed, 0, "no golden vector executed")
        XCTAssertEqual(failures, [])
    }
}
