import Foundation
import os

public actor EngramClient {
    public let baseURL: URL
    private let urlSession: URLSession

    /// Lossy wrapper: a malformed item decodes to `nil` instead of failing the whole array.
    private struct Failable<T: Decodable>: Decodable {
        let value: T?

        init(from decoder: Decoder) throws {
            do {
                value = try T(from: decoder)
            } catch {
                Logger(subsystem: "AllInGentleKit", category: "EngramClient")
                    .error("Skipping malformed Engram observation: \(String(describing: error))")
                value = nil
            }
        }
    }

    public init(
        baseURL: URL = URL(string: "http://127.0.0.1:7437")!,
        urlSession: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.urlSession = urlSession
    }

    public func health() async throws -> Bool {
        let url = baseURL.appendingPathComponent("health")
        let (_, response) = try await urlSession.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw AllInGentleError.sourceUnavailable("Engram health returned non-200 status")
        }
        return true
    }

    public func search(query: String, limit: Int = 20) async throws -> [MemoryObservation] {
        guard var components = URLComponents(
            url: baseURL.appendingPathComponent("search"),
            resolvingAgainstBaseURL: true
        ) else {
            throw AllInGentleError.invalidConfiguration("Invalid Engram search URL")
        }
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "limit", value: String(limit))
        ]
        guard let url = components.url else {
            throw AllInGentleError.invalidConfiguration("Invalid Engram search URL")
        }
        let (data, response) = try await urlSession.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw AllInGentleError.sourceUnavailable("Engram search failed")
        }
        return try parseObservations(data)
    }

    public func observations(project: String, limit: Int = 20) async throws -> [MemoryObservation] {
        let all = try await search(query: project, limit: limit)
        return all.filter { $0.project == project }
    }

    public func projects() async throws -> [Project] {
        try await projects(limit: 1000)
    }

    public func projects(limit: Int = 1000) async throws -> [Project] {
        let observations = try await search(query: "", limit: limit)
        let projectNames = observations.compactMap(\.project)
        let unique = Set(projectNames)
        return unique.sorted().map { name in
            Project(
                id: name,
                name: name,
                path: name,
                source: .engram,
                lastModified: nil
            )
        }
    }

    private func parseObservations(_ data: Data) throws -> [MemoryObservation] {
        let items = try JSONDecoder().decode([Failable<EngramObservation>]?.self, from: data) ?? []
        return items.compactMap(\.value).map(\.memoryObservation)
    }
}
