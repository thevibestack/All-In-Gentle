import Foundation

/// `URLProtocol` subclass that answers every request from the shared
/// `HandlerBox`, keeping the per-test handler out of a mutable static.
public final class MockURLProtocol: URLProtocol {
    public static let box = HandlerBox()

    override public class func canInit(with request: URLRequest) -> Bool { true }

    override public class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override public func startLoading() {
        do {
            let (response, data) = try Self.box.call(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override public func stopLoading() {}
}
