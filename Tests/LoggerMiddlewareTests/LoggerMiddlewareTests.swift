import XCTest
import SwiftRex
@testable import LoggerMiddleware

struct TestState: Equatable {
    public let a: Substate
    public let b: [Int]
    public let c: String
}

struct Substate: Equatable {
    public let x: Set<String>
    public let y: [String: Int]
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
                                                                                            y: ["one": 1, "eleven": 11],
                                                                                            z: true),
                                                                                b: [0, 1],
                                                                                c: "Foo")
        let afterState: LoggerMiddleware<TestMiddleware>.StateType = TestState(a: Substate(x: ["SetB", "SetC"],
                                                                                           y: ["one": 1, "twelve": 12],
                                                                                           z: false),
                                                                                b: [0],
                                                                                c: "Bar")

        // when
        let result: String? = LoggerMiddleware<TestMiddleware>.recursiveDiff(prefixLines: "🏛", stateName: "TestState", before: beforeState, after: afterState)

        // then
        let expected = """
                       🏛 TestState.some.a.x: 📦 <SetA, SetB> → <SetB, SetC>
                       🏛 TestState.some.a.y: 📦 [eleven: 11, one: 1] → [one: 1, twelve: 12]
                       🏛 TestState.some.a.z: true → false
                       🏛 TestState.some.b: 📦 [0, 1] → [0]
                       🏛 TestState.some.c: Foo → Bar
                       """
        XCTAssertEqual(result, expected)
    }

    static var allTests = [
        ("testStateDiff", testStateDiff),
    ]
}
