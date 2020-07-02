import Foundation
import os.log
import SwiftRex

extension Middleware where StateType: Equatable {
    public func logger(
        actionTransform: @escaping (InputActionType, ActionSource) -> String = {
            "\n🕹 \($0)\n🎪 \($1.file.split(separator: "/").last ?? ""):\($1.line) \($1.function)"
        },
        actionPrinter: @escaping (String) -> Void = { os_log(.debug, log: .default, "%{PUBLIC}@", $0) },
        stateDiffTransform: @escaping (StateType?, StateType) -> String? = {
            let stateBefore = dumpToString($0)
            let stateAfter =  dumpToString($1)
            return Difference.diff(old: stateBefore, new: stateAfter, linesOfContext: 2, prefixLines: "🏛 ")
        },
        stateDiffPrinter: @escaping (String?) -> Void = { state in
            if let state = state {
                os_log(.debug, log: .default, "%{PUBLIC}@", state)
            } else {
                os_log(.debug, log: .default, "%{PUBLIC}@", "🏛 No state mutation")
            }
        },
        queue: DispatchQueue = .main
    ) -> LoggerMiddleware<Self, InputActionType, OutputActionType, StateType> {
        LoggerMiddleware(
            self,
            actionTransform: actionTransform,
            actionPrinter: actionPrinter,
            stateDiffTransform: stateDiffTransform,
            stateDiffPrinter: stateDiffPrinter,
            queue: queue
        )
    }
}

public final class LoggerMiddleware<M: Middleware, InputActionType, OutputActionType, StateType: Equatable>
where M.StateType == StateType, M.InputActionType ==InputActionType, M.OutputActionType == OutputActionType {
    private let middleware: M
    private let queue: DispatchQueue
    private var getState: GetState<StateType>?
    private let actionTransform: (InputActionType, ActionSource) -> String
    private let actionPrinter: (String) -> Void
    private let stateDiffTransform: (StateType?, StateType) -> String?
    private let stateDiffPrinter: (String?) -> Void

    init(
        _ middleware: M,
        actionTransform: @escaping (InputActionType, ActionSource) -> String,
        actionPrinter: @escaping (String) -> Void,
        stateDiffTransform: @escaping (StateType?, StateType) -> String?,
        stateDiffPrinter: @escaping (String?) -> Void,
        queue: DispatchQueue
    ) {
        self.middleware = middleware
        self.actionTransform = actionTransform
        self.actionPrinter = actionPrinter
        self.stateDiffTransform = stateDiffTransform
        self.stateDiffPrinter = stateDiffPrinter
        self.queue = queue
    }

    public func receiveContext(getState: @escaping GetState<StateType>, output: AnyActionHandler<OutputActionType>) {
        self.getState = getState
        middleware.receiveContext(getState: getState, output: output)
    }

    public func handle(action: InputActionType, from dispatcher: ActionSource, afterReducer: inout AfterReducer) {
        let stateBefore = getState?()
        var innerAfterReducer = AfterReducer.doNothing()

        middleware.handle(action: action, from: dispatcher, afterReducer: &innerAfterReducer)

        afterReducer = innerAfterReducer <> .do { [weak self] in
            guard let self = self,
                  let stateAfter = self.getState?() else { return }

            self.queue.async {
                let actionMessage = self.actionTransform(action, dispatcher)
                self.actionPrinter(actionMessage)
                self.stateDiffPrinter(self.stateDiffTransform(stateBefore, stateAfter))
            }
        }
    }
}

extension LoggerMiddleware where M == IdentityMiddleware<InputActionType, OutputActionType, StateType> {
    public convenience init(
        actionTransform: @escaping (InputActionType, ActionSource) -> String = {
            "\n🕹 \($0)\n🎪 \($1.file.split(separator: "/").last ?? ""):\($1.line) \($1.function)"
        },
        actionPrinter: @escaping (String) -> Void = { os_log(.debug, log: .default, "%{PUBLIC}@", $0) },
        stateDiffTransform: @escaping (StateType?, StateType) -> String? = {
            let stateBefore = dumpToString($0)
            let stateAfter =  dumpToString($1)
            return Difference.diff(old: stateBefore, new: stateAfter, linesOfContext: 2, prefixLines: "🏛 ")
        },
        stateDiffPrinter: @escaping (String?) -> Void = { state in
            if let state = state {
                os_log(.debug, log: .default, "%{PUBLIC}@", state)
            } else {
                os_log(.debug, log: .default, "%{PUBLIC}@", "🏛 No state mutation")
            }
        },
        queue: DispatchQueue = .main
    ) {
        self.init(IdentityMiddleware(),
                  actionTransform: actionTransform,
                  actionPrinter: actionPrinter,
                  stateDiffTransform: stateDiffTransform,
                  stateDiffPrinter: stateDiffPrinter,
                  queue: queue)
    }
}
