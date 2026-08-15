import XCTest
@testable import AllInGentleKit

/// Unit tests for the pure keychain-load diagnostic mapping extracted from
/// `AISettingsView.load` (spec R5 settings-diagnostics).
///
/// The mapping is the only part of the load error path that carries logic, so
/// it is tested directly instead of driving the private, `onAppear`-triggered
/// `load()` through a UI harness.
@MainActor
final class AISettingsViewDiagnosticsTests: XCTestCase {
    /// A missing item is not an error: `load` returns nil, the API key field
    /// stays empty, and no "key not found" message is shown (R5).
    func testMissingKeyProducesNoValidationMessage() {
        let message = AISettingsView.keychainLoadDiagnostic(for: .success(nil))
        XCTAssertNil(message)
    }

    /// An auth/interaction failure surfaces the real diagnostic carried by the
    /// keychain store error, not a generic "no key" signal (R5).
    func testAuthFailureSurfacesRealDiagnostic() {
        let error = AllInGentleError.persistenceFailure("Keychain load failed: -25308")
        let message = AISettingsView.keychainLoadDiagnostic(for: .failure(error))
        XCTAssertEqual(message, "Keychain load failed: -25308")
    }

    /// Any other error falls back to a generic localized message.
    func testOtherErrorsFallBackToGenericMessage() {
        let error = AllInGentleError.invalidConfiguration("unexpected error")
        let message = AISettingsView.keychainLoadDiagnostic(for: .failure(error))
        XCTAssertEqual(message, L("settings.ai.error.keychainLoadFailed"))
    }
}
