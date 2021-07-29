import Foundation
import os.log
import SwiftRex

extension Middleware where StateType: Equatable {
    public func logger(
        actionTransform: LoggerMiddleware<Self>.ActionTransform = .default(),
        actionPrinter: LoggerMiddleware<Self>.ActionLogger = .osLog,
        actionFilter: @escaping (InputActionType) -> Bool = { _ in true },
        stateDiffTransform: LoggerMiddleware<Self>.StateDiffTransform = .diff(),
        stateDiffPrinter: LoggerMiddleware<Self>.StateLogger = .osLog,
        queue: DispatchQueue = .main
    ) -> LoggerMiddleware<Self> {
        LoggerMiddleware(
            self,
            actionTransform: actionTransform,
            actionPrinter: actionPrinter,
            actionFilter: actionFilter,
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
    private let actionFilter: (InputActionType) -> Bool
    private let stateDiffTransform: StateDiffTransform
    private let stateDiffPrinter: StateLogger

    init(
        _ middleware: M,
        actionTransform: ActionTransform,
        actionPrinter: ActionLogger,
        actionFilter: @escaping (InputActionType) -> Bool = { _ in true },
        stateDiffTransform: StateDiffTransform,
        stateDiffPrinter: StateLogger,
        queue: DispatchQueue
    ) {
        self.middleware = middleware
        self.actionTransform = actionTransform
        self.actionPrinter = actionPrinter
        self.actionFilter = actionFilter
        self.stateDiffTransform = stateDiffTransform
        self.stateDiffPrinter = stateDiffPrinter
        self.queue = queue
    }

    public func receiveContext(getState: @escaping GetState<StateType>, output: AnyActionHandler<OutputActionType>) {
        self.getState = getState
        middleware.receiveContext(getState: getState, output: output)
    }

    public func handle(action: InputActionType, from dispatcher: ActionSource, afterReducer: inout AfterReducer) {
        guard actionFilter(action) else { return }
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
        actionFilter: @escaping (InputActionType) -> Bool = { _ in true },
        stateDiffTransform: LoggerMiddleware<IdentityMiddleware<InputActionType, OutputActionType, StateType>>.StateDiffTransform = .diff(),
        stateDiffPrinter: LoggerMiddleware<IdentityMiddleware<InputActionType, OutputActionType, StateType>>.StateLogger = .osLog,
        queue: DispatchQueue = .main
    ) -> LoggerMiddleware<IdentityMiddleware<InputActionType, OutputActionType, StateType>> {
        .init(
            IdentityMiddleware(),
            actionTransform: actionTransform,
            actionPrinter: actionPrinter,
            actionFilter: actionFilter,
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
        /// Logs using os_log.
        case osLog
        /// Appends the messages to a file. The file must exist!
        case file(FileAppender)
        /// A custom handler.
        case custom((String) -> Void)

        func log(state: String) {
            switch self {
            case .osLog: LoggerMiddleware.osLog(state)
            case let .file(fileAppender): fileAppender.write(state)
            case let .custom(closure): closure(state)
            }
        }
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
            let leftSorted: [String] = left.map { (lft: AnyHashable) in "\(lft)" }.sorted { a, b in a < b }
            let rightSorted: [String] = right.map { (rgt: AnyHashable) in "\(rgt)" }.sorted { a, b in a < b }

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
        let strings: [String] = leftMirror.children.map({ (leftChild: Mirror.Child) -> String? in
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
            // filter diffLine if it contains a filterString
            false == (filters ?? []).contains(where: { (filterString: String) -> Bool in
                diffLine.contains(filterString)
            })
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
        /// Logs using os_log.
        case osLog
        /// Appends the messages to a file. The file must exist!
        case file(FileAppender)
        /// A custom handler.
        case custom((String) -> Void)

        func log(action: String) {
            switch self {
            case .osLog: LoggerMiddleware.osLog(action)
            case let .file(fileappender): fileappender.write(action)
            case let .custom(closure): closure(action)
            }
        }
    }
}

// MARK: Action Transform
extension LoggerMiddleware {
    public enum ActionTransform {
        case `default`(actionPrefix: String = "🕹 ", sourcePrefix: String = " 🎪 ")
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

// MARK: Log output

extension LoggerMiddleware {

    fileprivate static func osLog(_ message: String) {
        os_log(.debug, log: .default, "%{PUBLIC}@", message)
    }

}

public struct FileAppender {
    private let url: URL
    private let date: () -> Date
    private let dateFormatter: DateFormatter
    private let writer: (URL, Data) -> Void

    public init(url: URL, date: @escaping () -> Date, dateFormatter: DateFormatter, writer: @escaping (URL, Data) -> Void) {
        self.url = url
        self.date = date
        self.dateFormatter = dateFormatter
        self.writer = writer
    }

    public func write(_ message: String) {
        guard let data = (dateFormatter.string(from: date()) + " " + message + "\n").data(using: String.Encoding.utf8) else { return }
        writer(url, data)
    }
}

extension FileAppender {
    public static func live(url: URL, dateFormatter: DateFormatter = .init(), date: @escaping () -> Date = Date.init, fileHandle: @escaping (URL) throws -> FileHandle = FileHandle.init(forUpdating:)) -> FileAppender {
        FileAppender(
            url: url,
            date: date,
            dateFormatter: dateFormatter,
            writer: { url, data in
                guard let fileUpdater = try? fileHandle(url) else { return }
                fileUpdater.seekToEndOfFile()
                fileUpdater.write(data)
                fileUpdater.closeFile()
            }
        )
    }
}

