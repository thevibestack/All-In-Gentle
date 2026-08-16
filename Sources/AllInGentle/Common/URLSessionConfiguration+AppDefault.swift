import Foundation

/// Shared network defaults for all app clients.
///
/// - Note: `timeoutIntervalForRequest` (30s) is an idle timeout — it resets
///   every time data arrives, so SSE streams only trip it when the server
///   stalls more than 30s between chunks.
public extension URLSessionConfiguration {
    public static func makeAppDefault() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 600
        configuration.waitsForConnectivity = true
        configuration.httpMaximumConnectionsPerHost = 4
        return configuration
    }
}
