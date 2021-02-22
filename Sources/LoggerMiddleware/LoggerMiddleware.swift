import Foundation
import os.log
import SwiftRex

extension Middleware where StateType: Equatable {
    public func logger(
        actionTransform: LoggerMiddleware<Self>.ActionTransform = .default(),
        actionPrinter: LoggerMiddleware<Self>.ActionLogger = .osLog,
        stateDiffTransform: LoggerMiddleware<Self>.StateDiffTransform = .diff(),
        stateDiffPrinter: LoggerMiddleware<Self>.StateLogger = .osLog,
        queue: DispatchQueue = .main
    ) -> LoggerMiddleware<Self> {
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

public final class LoggerMiddleware<M: Middleware>: Middleware where M.StateType: Equatable {
    public typealias InputActionType = M.InputActionType
    public typealias OutputActionType = M.OutputActionType
    public typealias StateType = M.StateType
    private let middleware: M
    private let queue: DispatchQueue
    private var getState: GetState<StateType>?
    private let actionTransform: ActionTransform
    private let actionPrinter: ActionLogger
    private let stateDiffTransform: StateDiffTransform
    private let stateDiffPrinter: StateLogger

    init(
        _ middleware: M,
        actionTransform: ActionTransform,
        actionPrinter: ActionLogger,
        stateDiffTransform: StateDiffTransform,
        stateDiffPrinter: StateLogger,
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
                let actionMessage = self.actionTransform.transform(action: action, source: dispatcher)
                self.actionPrinter.log(action: actionMessage)
                if let diffString = self.stateDiffTransform.transform(oldState: stateBefore, newState: stateAfter) {
                    self.stateDiffPrinter.log(state: diffString)
                }
            }
        }
    }
}

extension LoggerMiddleware {
    public static func `default`(
        actionTransform: LoggerMiddleware<IdentityMiddleware<InputActionType, OutputActionType, StateType>>.ActionTransform = .default(),
        actionPrinter: LoggerMiddleware<IdentityMiddleware<InputActionType, OutputActionType, StateType>>.ActionLogger = .osLog,
        stateDiffTransform: LoggerMiddleware<IdentityMiddleware<InputActionType, OutputActionType, StateType>>.StateDiffTransform = .diff(),
        stateDiffPrinter: LoggerMiddleware<IdentityMiddleware<InputActionType, OutputActionType, StateType>>.StateLogger = .osLog,
        queue: DispatchQueue = .main
    ) -> LoggerMiddleware<IdentityMiddleware<InputActionType, OutputActionType, StateType>> {
        .init(
            IdentityMiddleware(),
            actionTransform: actionTransform,
            actionPrinter: actionPrinter,
            stateDiffTransform: stateDiffTransform,
            stateDiffPrinter: stateDiffPrinter,
            queue: queue
        )
    }
}

// MARK: - State
// MARK: State Logger
extension LoggerMiddleware {
    public enum StateLogger {
        case osLog
        case file(URL)
        case custom((String) -> Void)

        func log(state: String) {
            switch self {
            case .osLog: LoggerMiddleware.osLog(state: state)
            case let .file(url): LoggerMiddleware.fileLog(state: state, to: url)
            case let .custom(closure): closure(state)
            }
        }
    }

    private static func osLog(state: String) {
        os_log(.debug, log: .default, "%{PUBLIC}@", state)
    }

    private static func fileLog(state: String, to fileURL: URL) {
        try? state.write(toFile: fileURL.absoluteString, atomically: false, encoding: .utf8)
    }
}

// MARK: State Diff Transform
extension LoggerMiddleware {
    public enum StateDiffTransform {
        case diff(linesOfContext: Int = 2, prefixLines: String = "🏛 ")
        case newStateOnly
        case custom((StateType?, StateType) -> String?)

        func transform(oldState: StateType?, newState: StateType) -> String? {
            switch self {
            case let .diff(linesOfContext, prefixLines):
                let stateBefore = dumpToString(oldState)
                let stateAfter =  dumpToString(newState)
                return Difference.diff(old: stateBefore, new: stateAfter, linesOfContext: linesOfContext, prefixLines: prefixLines)
                ?? "\(prefixLines) No state mutation"
            case .newStateOnly:
                return dumpToString(newState)
            case let .custom(closure):
                return closure(oldState, newState)
            }
        }
    }
}

// MARK: - Action
// MARK: Action Logger
extension LoggerMiddleware {
    public enum ActionLogger {
        case osLog
        case file(URL)
        case custom((String) -> Void)

        func log(action: String) {
            switch self {
            case .osLog: LoggerMiddleware.osLog(action: action)
            case let .file(url): LoggerMiddleware.fileLog(action: action, to: url)
            case let .custom(closure): closure(action)
            }
        }
    }

    private static func osLog(action: String) {
        os_log(.debug, log: .default, "%{PUBLIC}@", action)
    }

    private static func fileLog(action: String, to fileURL: URL) -> Void {
        try? action.write(toFile: fileURL.absoluteString, atomically: false, encoding: .utf8)
    }
}

// MARK: Action Transform
extension LoggerMiddleware {
    public enum ActionTransform {
        case `default`(actionPrefix: String = "\n🕹 ", sourcePrefix: String = "\n🎪 ")
        case actionNameOnly
        case custom((InputActionType, ActionSource) -> String)

        func transform(action: InputActionType, source: ActionSource) -> String {
            switch self {
            case let .default(actionPrefix, sourcePrefix):
                return "\(actionPrefix)\(action)\(sourcePrefix)\(source.file.split(separator: "/").last ?? ""):\(source.line) \(source.function)"
            case .actionNameOnly:
                return "\(action)"
            case let .custom(closure):
                return closure(action, source)
            }
        }
    }
}
