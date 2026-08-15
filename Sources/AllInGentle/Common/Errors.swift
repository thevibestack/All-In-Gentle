import Foundation

public enum AllInGentleError: Error, Sendable, Equatable {
    case readOnlyViolation
    case sourceUnavailable(String)
    case invalidConfiguration(String)
    case persistenceFailure(String)
}

extension AllInGentleError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .readOnlyViolation:
            return L("errors.readOnlyViolation")
        case .sourceUnavailable(let detail):
            return L("errors.sourceUnavailable", detail)
        case .invalidConfiguration(let detail):
            return L("errors.invalidConfiguration", detail)
        case .persistenceFailure(let detail):
            return L("errors.persistenceFailure", detail)
        }
    }
}
