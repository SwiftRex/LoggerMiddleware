# LoggerMiddleware

## Usage

### Simple usage, logging all actions and state changes for whole app
```swift
LoggerMiddleware() <> MyOtherMiddleware().lift(...)
```

### Log a single middleware, only actions and state within that middleware field
```swift
MyOtherMiddleware().logger().lift(...)
```

### Log a single middleware, but including actions and state changes for the whole app
(same as adding LoggerMiddleware in the chain as seen in the first option)
```swift
MyOtherMiddleware().lift(...).logger()
```

### Log a specific group of actions and state tree
```swift
IdentityMiddleware<InterestingAction, InterestingAction, InterestingState>()
    .logger()
    .lift(...) // lift InterestingAction and InterestingState to AppAction and AppState
<> MyOtherMiddleware().lift(...)
```

## Parameters

### actionTransform
Gives the Input Action and Action Source to be formatted as a string.

Default:
```swift
actionTransform: @escaping (InputActionType, ActionSource) -> String = {
    "\n🕹 \($0)\n🎪 \($1.file.split(separator: "/").last ?? ""):\($1.line) \($1.function)"
}
```

### actionPrinter
Gives the action and action source string, formatted from previous parameter, to be logged or saved into a file 

Default:
```swift
actionPrinter: @escaping (String) -> Void = { os_log(.debug, log: .default, "%{PUBLIC}@", $0) }
```

### stateDiffTransform
Gives the previous state, and the state after the reducers have changed it, so a diff string can be created.
`Difference`  struct contains helpers to compare multiline strings, and `dumpToString` free function is a helper to stringify anything.
Alternatively you could stringify using JSONEncoder or any other tool. Be careful with performance, or provide an alternative queue
to avoid locking the main queue with heavy log task.
Returning `nil` means that nothing has changed.
The default logger will give a "git diff" output, containing + and - for changed lines, including 2 lines of context before and after the change.

Default:
```swift
stateDiffTransform: @escaping (StateType?, StateType) -> String? = {
    let stateBefore = dumpToString($0)
    let stateAfter =  dumpToString($1)
    return Difference.diff(old: stateBefore, new: stateAfter, linesOfContext: 2, prefixLines: "🏛 ")
}
```

### stateDiffPrinter 

Gives the state diff string, formatted from previous parameter, to be logged or saved into a file.
Receiving `nil` means that the state hasn't changed with this action.

Default:
```swift
stateDiffPrinter: @escaping (String?) -> Void = { state in
    if let state = state {
        os_log(.debug, log: .default, "%{PUBLIC}@", state)
    } else {
        os_log(.debug, log: .default, "%{PUBLIC}@", "🏛 No state mutation")
    }
}
```

### queue

The queue to run the string transformation and printer. Use an alternative, low priority, serial queue to avoid locking the UI
with logging operations.

Default:
```swift
queue: DispatchQueue = .main
```
