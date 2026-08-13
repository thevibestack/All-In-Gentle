import Foundation

public actor EngramClient {
    public let baseURL: URL
    private let urlSession: URLSession

    private static let engramDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

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
        let raw = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] ?? []
        return raw.compactMap { item in
            let id = (item["sync_id"] as? String) ?? (item["id"].map { String(describing: $0) } ?? UUID().uuidString)
            guard let title = item["title"] as? String,
                  let content = item["content"] as? String else {
                return nil
            }
            let project = item["project"] as? String
            let tags = (item["tags"] as? [String]) ?? []
            let createdAt: Date
            if let dateString = item["created_at"] as? String,
               let date = Self.engramDateFormatter.date(from: dateString) {
                createdAt = date
            } else if let dateString = item["updated_at"] as? String,
                      let date = Self.engramDateFormatter.date(from: dateString) {
                createdAt = date
            } else {
                createdAt = Date()
            }
            return MemoryObservation(
                id: id,
                title: title,
                content: content,
                project: project,
                tags: tags,
                createdAt: createdAt
            )
        }
    }
}
