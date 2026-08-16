import Foundation
import AllInGentleKit

/// In-memory `EngramSearchProvider` double.
///
/// The three-argument overload filters by `project` — mirroring the
/// protocol's default-extension behavior — and records the applied filter so
/// tests can assert provider-side scoping. `FilteringStub` in
/// WikiViewModelTests remains the intentional single-use probe for the
/// default extension.
public actor EngramSearchProviderStub: EngramSearchProvider {
    private var results: [MemoryObservation]
    private var sleepDuration: Duration
    private var thrownError: Error?
    public private(set) var lastQuery: String?
    public private(set) var lastProject: String?
    public private(set) var capturedProjectFilter: String?
    public private(set) var capturedSearchQuery: String?
    public private(set) var capturedObservationsProject: String?
    public private(set) var capturedObservationsLimit: Int?
    private var observationsResults: [MemoryObservation]

    public init(
        results: [MemoryObservation] = [],
        observationsResults: [MemoryObservation] = [],
        sleepDuration: Duration = .seconds(0),
        thrownError: Error? = nil
    ) {
        self.results = results
        self.observationsResults = observationsResults
        self.sleepDuration = sleepDuration
        self.thrownError = thrownError
    }

    public func search(query: String, limit: Int) async throws -> [MemoryObservation] {
        try await Task.sleep(for: sleepDuration)
        if let thrownError { throw thrownError }
        lastQuery = query
        return results
    }

    public func search(query: String, limit: Int, project: String?) async throws -> [MemoryObservation] {
        capturedProjectFilter = project
        capturedSearchQuery = query
        lastProject = project
        try await Task.sleep(for: sleepDuration)
        if let thrownError { throw thrownError }
        if let project {
            return results.filter { $0.project == project }
        }
        return results
    }

    public func observations(project: String, limit: Int) async throws -> [MemoryObservation] {
        capturedObservationsProject = project
        capturedObservationsLimit = limit
        try await Task.sleep(for: sleepDuration)
        if let thrownError { throw thrownError }
        return observationsResults
    }
}
