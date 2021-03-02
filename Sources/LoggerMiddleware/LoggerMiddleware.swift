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
        case recursive(prefixLines: String = "🏛 ", stateName: String, filters: [String]? = nil)
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
            case let .recursive(prefixLines, stateName, filters):
                return recursiveDiff(prefixLines: prefixLines, stateName: stateName, filters: filters, before: oldState, after: newState)
            case let .custom(closure):
                return closure(oldState, newState)
            }
        }
    }

    public static func recursiveDiff(prefixLines: String, stateName: String, filters: [String]? = nil, before: StateType?, after: StateType) -> String? {
        // cuts the redundant newline character from the output
        diff(prefix: prefixLines, name: stateName, filters: filters, lhs: before, rhs: after)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func diff<A>(prefix: String, name: String, level: Int = 0, filters: [String]? = nil, lhs: A?, rhs: A?) -> String? {

        guard let rightHandSide = rhs, let leftHandSide = lhs else {
            if let rightHandSide = rhs {
                return "\(prefix).\(name): nil → \(rightHandSide)"
            }

            if let leftHandSide = lhs {
                return "\(prefix).\(name): \(leftHandSide) → nil"
            }

            // nil == lhs == rhs
            return nil
        }

        // special handling for Dictionaries: stringify and order the keys before comparing
        if let left = leftHandSide as? Dictionary<AnyHashable, Any>, let right = rightHandSide as? Dictionary<AnyHashable, Any> {

            let leftSorted = left.sorted { a, b in "\(a.key)" < "\(b.key)" }
            let rightSorted = right.sorted { a, b in "\(a.key)" < "\(b.key)" }

            let leftPrintable = leftSorted.map { key, value in "\(key): \(value)" }.joined(separator: ", ")
            let rightPrintable = rightSorted.map { key, value in "\(key): \(value)" }.joined(separator: ", ")

            // .difference(from:) gives unpleasant results
            if leftPrintable == rightPrintable {
                return nil
            }

            return "\(prefix).\(name): 📦 [\(leftPrintable)] → [\(rightPrintable)]"
        }

        // special handling for sets as well: order the contents, compare as strings
        if let left = leftHandSide as? Set<AnyHashable>, let right = rightHandSide as? Set<AnyHashable> {
            let leftSorted = left.map { "\($0)" }.sorted { a, b in a < b }
            let rightSorted = right.map { "\($0)" }.sorted { a, b in a < b }

            let leftPrintable = leftSorted.joined(separator: ", ")
            let rightPrintable = rightSorted.joined(separator: ", ")

            // .difference(from:) gives unpleasant results
            if leftPrintable == rightPrintable {
                return nil
            }
            return "\(prefix).\(name): 📦 <\(leftPrintable)> → <\(rightPrintable)>"
        }

        let leftMirror = Mirror(reflecting: leftHandSide)
        let rightMirror = Mirror(reflecting: rightHandSide)

        // if there are no children, compare leftHandSide and rightHandSide directly
        if 0 == leftMirror.children.count {
            if "\(leftHandSide)" == "\(rightHandSide)" {
                return nil
            } else {
                return "\(prefix).\(name): \(leftHandSide) → \(rightHandSide)"
            }
        }

        // there are children -> diff the object graph recursively
        let strings: [String] = leftMirror.children.map({ leftChild  in
            let toDotOrNotToDot = (level > 0) ? "." : " "
            return Self.diff(prefix: "\(prefix)\(toDotOrNotToDot)\(name)",
                             name: leftChild.label ?? "#", // label might be missing for items in collections, # represents a collection element
                             level: level + 1,
                             filters: filters,
                             lhs: leftChild.value,
                             rhs: rightMirror.children.first(where: { $0.label == leftChild.label })?.value)
        })
        .compactMap { $0 }
        .filter { (diffLine: String) -> Bool in
            if nil == filters?.first(where: { filterString in
                diffLine.contains(filterString)
            }) {
                return true
            }
            return false
        }

        if strings.count > 0 {
            return strings.joined(separator: "\n")
        }
        return nil
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
