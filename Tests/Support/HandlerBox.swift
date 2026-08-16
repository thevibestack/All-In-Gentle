import Foundation

/// Per-instance handler box shared with `MockURLProtocol`.
///
/// `URLSession` instantiates `URLProtocol` subclasses via
/// `init(request:cachedResponse:client:)`, so the handler cannot be injected
/// through an initializer. A single immutable `static let` reference with
/// NSLock-guarded interior mutability avoids the `nonisolated(unsafe) static
/// var` data-race pattern (F22): the box is a constant, not a mutable static.
public final class HandlerBox: @unchecked Sendable {
    private let lock = NSLock()
    private var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    public init() {}

    public func set(_ handler: @escaping (URLRequest) throws -> (HTTPURLResponse, Data)) {
        lock.withLock { self.handler = handler }
    }

    public func call(_ request: URLRequest) throws -> (HTTPURLResponse, Data) {
        lock.lock()
        defer { lock.unlock() }
        guard let handler else { throw URLError(.resourceUnavailable) }
        return try handler(request)
    }
}
