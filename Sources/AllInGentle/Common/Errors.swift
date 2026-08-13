public enum AllInGentleError: Error, Sendable {
    case readOnlyViolation
    case sourceUnavailable(String)
    case invalidConfiguration(String)
}
