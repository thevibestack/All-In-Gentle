import Foundation

public struct AsyncTimerSequence<C: Clock>: AsyncSequence {
    public typealias Element = C.Instant

    private let interval: C.Duration
    private let clock: C

    public init(interval: C.Duration, clock: C) {
        self.interval = interval
        self.clock = clock
    }

    public func makeAsyncIterator() -> Iterator {
        Iterator(interval: interval, clock: clock)
    }

    public struct Iterator: AsyncIteratorProtocol {
        private let interval: C.Duration
        private let clock: C

        init(interval: C.Duration, clock: C) {
            self.interval = interval
            self.clock = clock
        }

        public mutating func next() async throws -> C.Instant? {
            let deadline = clock.now.advanced(by: interval)
            try await Task.sleep(until: deadline, tolerance: nil, clock: clock)
            return deadline
        }
    }
}
