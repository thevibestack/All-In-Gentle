import Foundation

/// Creates a fresh, suite-named `UserDefaults` for hermetic tests.
///
/// Each call uses a unique suite name, so tests never share or leak
/// persisted values.
public func makeEphemeralDefaults() -> UserDefaults {
    UserDefaults(suiteName: "all-in-gentle-tests-\(UUID().uuidString)")!
}
