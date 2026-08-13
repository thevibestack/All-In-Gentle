import Foundation

/// Returns a localized string from the `Localizable` string catalog in the module bundle.
public func L(_ key: String, comment: String = "") -> String {
    NSLocalizedString(key, bundle: .module, comment: comment)
}

/// Returns a formatted localized string from the `Localizable` string catalog in the module bundle.
public func L(_ key: String, _ arguments: CVarArg...) -> String {
    String(format: L(key, comment: ""), locale: Locale.current, arguments: arguments)
}
