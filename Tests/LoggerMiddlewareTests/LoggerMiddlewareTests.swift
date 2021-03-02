import XCTest
import SwiftRex
@testable import LoggerMiddleware

struct TestState: Equatable {
    public let a: Substate
    public let b: [Int]
    public let c: String
    public let d: String?
    public let e: String?
}

struct Substate: Equatable {
    public let x: Set<String>
    public let y1: [String: Int]
    public let y2: [String: Int?]
    public let z: Bool
}

struct TestMiddleware: Middleware {
    func receiveContext(getState: @escaping GetState<TestState>, output: AnyActionHandler<Int>) {
    }

    func handle(action: Int, from dispatcher: ActionSource, afterReducer: inout AfterReducer) {
    }

    typealias InputActionType = Int
    typealias OutputActionType = Int
    typealias StateType = TestState
}

final class LoggerMiddlewareTests: XCTestCase {

    func testStateDiff() {
        // given
        let beforeState: LoggerMiddleware<TestMiddleware>.StateType = TestState(a: Substate(x: ["SetB", "SetA"],
                                                                                            y1: ["one": 1, "eleven": 11],
                                                                                            y2: ["one": 1, "eleven": 11, "zapp": 42],
                                                                                            z: true),
                                                                                b: [0, 1],
                                                                                c: "Foo",
                                                                                d: "✨",
                                                                                e: nil)
        let afterState: LoggerMiddleware<TestMiddleware>.StateType = TestState(a: Substate(x: ["SetB", "SetC"],
                                                                                           y1: ["one": 1, "twelve": 12],
                                                                                           y2: ["one": 1, "twelve": 12, "zapp": nil],
                                                                                           z: false),
                                                                                b: [0],
                                                                                c: "Bar",
                                                                                d: nil,
                                                                                e: "🥚")

        // when
        let result: String? = LoggerMiddleware<TestMiddleware>.recursiveDiff(prefixLines: "🏛", stateName: "TestState", before: beforeState, after: afterState)

        // then
        let expected = """
                       🏛 TestState.a.x: 📦 <SetA, SetB> → <SetB, SetC>
                       🏛 TestState.a.y1: 📦 [eleven: 11, one: 1] → [one: 1, twelve: 12]
                       🏛 TestState.a.y2: 📦 [eleven: Optional(11), one: Optional(1), zapp: Optional(42)] → [one: Optional(1), twelve: Optional(12), zapp: nil]
                       🏛 TestState.a.z: true → false
                       🏛 TestState.b.#: 1 → 0
                       🏛 TestState.c: Foo → Bar
                       🏛 TestState.d.some: ✨ → nil
                       🏛 TestState.e: nil → Optional("🥚")
                       """
        XCTAssertEqual(result, expected)
    }


    func testStateDiffWithFilters() {
        // given
        let beforeState: LoggerMiddleware<TestMiddleware>.StateType = TestState(a: Substate(x: ["SetB", "SetA"],
                                                                                            y1: ["one": 1, "eleven": 11],
                                                                                            y2: ["one": 1, "eleven": 11, "zapp": 42],
                                                                                            z: true),
                                                                                b: [0, 1],
                                                                                c: "Foo",
                                                                                d: "✨",
                                                                                e: nil)
        let afterState: LoggerMiddleware<TestMiddleware>.StateType = TestState(a: Substate(x: ["SetB", "SetC"],
                                                                                           y1: ["one": 1, "twelve": 12],
                                                                                           y2: ["one": 1, "twelve": 12, "zapp": nil],
                                                                                           z: false),
                                                                                b: [0],
                                                                                c: "Bar",
                                                                                d: nil,
                                                                                e: "🥚")

        // when
        let result: String? = LoggerMiddleware<TestMiddleware>.recursiveDiff(prefixLines: "🏛",
                                                                             stateName: "TestState",
                                                                             filters: [
                                                                                " TestState.a.y2",
                                                                                " TestState.b.#"
                                                                             ],
                                                                             before: beforeState,
                                                                             after: afterState)

        // then
        let expected = """
                       🏛 TestState.a.x: 📦 <SetA, SetB> → <SetB, SetC>
                       🏛 TestState.a.y1: 📦 [eleven: 11, one: 1] → [one: 1, twelve: 12]
                       🏛 TestState.a.z: true → false
                       🏛 TestState.c: Foo → Bar
                       🏛 TestState.d.some: ✨ → nil
                       🏛 TestState.e: nil → Optional("🥚")
                       """
        XCTAssertEqual(result, expected)
    }

    static var allTests = [
        ("testStateDiff", testStateDiff),
    ]
}
