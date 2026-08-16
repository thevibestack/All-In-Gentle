import Foundation

/// Polls `condition` until it returns `true` or `timeout` elapses.
///
/// Deadline-bounded: never polls unbounded. Returns `true` as soon as
/// `condition` holds; `false` when the deadline expires first.
public func waitUntil(
    timeout: Duration = .seconds(2),
    condition: @escaping @MainActor () async -> Bool
) async -> Bool {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    while !(await condition()), clock.now < deadline {
        await Task.yield()
    }
    return await condition()
}
