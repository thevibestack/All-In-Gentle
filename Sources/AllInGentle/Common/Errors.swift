public enum AllInGentleError: Error, Sendable, Equatable {
    case readOnlyViolation
    case sourceUnavailable(String)
    case invalidConfiguration(String)
    case persistenceFailure(String)
    case processTimedOut(String)
}
