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

    public func removeValue(for key: PreferenceKey) {
        queue.sync { defaults.removeObject(forKey: key.rawValue) }
    }

    public func codable<T: Codable>(for key: PreferenceKey) -> T? {
        queue.sync {
            guard let data = defaults.object(forKey: key.rawValue) as? Data else { return nil }
            return try? JSONDecoder().decode(T.self, from: data)
        }
    }

    public func setCodable<T: Codable>(_ value: T?, for key: PreferenceKey) {
        queue.sync {
            if let value {
                if let data = try? JSONEncoder().encode(value) {
                    defaults.set(data, forKey: key.rawValue)
                }
            } else {
                defaults.removeObject(forKey: key.rawValue)
            }
        }
    }

    // MARK: - Convenience accessors

    public var llmProviderConfiguration: LLMProviderConfiguration? {
        get { codable(for: .llmProviderConfiguration) }
        set { setCodable(newValue, for: .llmProviderConfiguration) }
    }

    public var openSpecRoot: String? {
        get { string(for: .openSpecRoot) }
        set {
            if let newValue {
                set(newValue, for: .openSpecRoot)
            } else {
                removeValue(for: .openSpecRoot)
            }
        }
    }

    public var onboardingCompleted: Bool {
        get { bool(for: .onboardingCompleted) }
        set { set(newValue, for: .onboardingCompleted) }
    }
}

public enum PreferenceKey: String, CaseIterable, Sendable {
    case selectedTab
    case lastProjectPath
    case chatProvider
    case onboardingDismissed
    case llmProviderConfiguration
    case openSpecRoot
    case onboardingCompleted
}
