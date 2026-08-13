import Foundation

public final class PreferencesStore: @unchecked Sendable {
    private let defaults: UserDefaults
    private let queue = DispatchQueue(label: "com.all-in-gentle.preferences")

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func string(for key: PreferenceKey) -> String? {
        queue.sync { defaults.string(forKey: key.rawValue) }
    }

    public func set(_ value: String, for key: PreferenceKey) {
        queue.sync { defaults.set(value, forKey: key.rawValue) }
    }

    public func integer(for key: PreferenceKey) -> Int {
        queue.sync { defaults.integer(forKey: key.rawValue) }
    }

    public func set(_ value: Int, for key: PreferenceKey) {
        queue.sync { defaults.set(value, forKey: key.rawValue) }
    }

    public func bool(for key: PreferenceKey) -> Bool {
        queue.sync { defaults.bool(forKey: key.rawValue) }
    }

    public func set(_ value: Bool, for key: PreferenceKey) {
        queue.sync { defaults.set(value, forKey: key.rawValue) }
    }
}

public enum PreferenceKey: String, CaseIterable, Sendable {
    case selectedTab
    case lastProjectPath
    case chatProvider
    case onboardingDismissed
}
