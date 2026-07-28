import Foundation

/// Where the pomodoro survives a quit.
///
/// The state is a value with a deadline in it, so persisting is just writing the value:
/// nothing has to be reconstructed on load beyond rolling the clock forward.
public protocol FocusStore {
    func load() -> PomodoroState?
    func save(_ state: PomodoroState)
}

public extension PomodoroState {
    /// Reads persisted state and rolls it forward to `now`.
    ///
    /// Returns the boundaries crossed while the app was not running, so the caller can
    /// decide whether any of them are still worth announcing. They usually are not.
    static func restored(from store: some FocusStore, at now: Date) -> (state: PomodoroState, missed: [FocusCompletion]) {
        var state = store.load() ?? PomodoroState()
        let missed = state.catchUp(at: now)
        return (state, missed)
    }
}

/// The shipping store. One JSON blob in user defaults, which is the right size of
/// persistence for a timer and needs no file coordination.
public struct UserDefaultsFocusStore: FocusStore {
    public static let defaultKey = "com.aliteo.topnotch.focus.state"

    private let defaults: UserDefaults
    private let key: String

    public init(defaults: UserDefaults = .standard, key: String = UserDefaultsFocusStore.defaultKey) {
        self.defaults = defaults
        self.key = key
    }

    public func load() -> PomodoroState? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(PomodoroState.self, from: data)
    }

    public func save(_ state: PomodoroState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        defaults.set(data, forKey: key)
    }
}
