public enum AllInGentleError: Error, Sendable, Equatable {
    case readOnlyViolation
    case sourceUnavailable(String)
    case invalidConfiguration(String)
}
