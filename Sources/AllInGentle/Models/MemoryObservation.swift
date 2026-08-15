import Foundation

public struct MemoryObservation: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public var title: String
    public var content: String
    public var project: String?
    public var tags: [String]
    public var createdAt: Date?

    public init(
        id: String,
        title: String,
        content: String,
        project: String? = nil,
        tags: [String] = [],
        createdAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.content = content
        self.project = project
        self.tags = tags
        self.createdAt = createdAt
    }
}

/// Typed mirror of an Engram observation payload (HTTP `GET /observations` / `/search`).
///
/// Identity (`id`) and dates (`created_at`/`updated_at`) are decoded strictly from the
/// payload — nothing is ever fabricated. Malformed items are skipped by the caller's
/// lossy decode policy (`Failable`), never crash the whole response.
public struct EngramObservation: Decodable, Sendable {
    public let id: EngramID
    public let syncID: String?
    public let title: String
    public let content: String
    public let project: String?
    public let tags: [String]
    public let createdAtRaw: String?
    public let updatedAtRaw: String?

    public enum CodingKeys: String, CodingKey {
        case id
        case syncID = "sync_id"
        case title
        case content
        case project
        case tags
        case createdAtRaw = "created_at"
        case updatedAtRaw = "updated_at"
    }

    /// Shared UTC formatter for Engram timestamp strings (`"yyyy-MM-dd HH:mm:ss"`).
    public static let engramDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(EngramID.self, forKey: .id)
        syncID = try container.decodeIfPresent(String.self, forKey: .syncID)
        title = try container.decode(String.self, forKey: .title)
        content = try container.decode(String.self, forKey: .content)
        project = try container.decodeIfPresent(String.self, forKey: .project)
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        createdAtRaw = try container.decodeIfPresent(String.self, forKey: .createdAtRaw)
        updatedAtRaw = try container.decodeIfPresent(String.self, forKey: .updatedAtRaw)
    }

    /// Parsed date; nil when neither raw timestamp is present or parseable — never `Date()`.
    public var createdAt: Date? {
        createdAtRaw.flatMap(Self.engramDateFormatter.date(from:))
            ?? updatedAtRaw.flatMap(Self.engramDateFormatter.date(from:))
    }

    /// Canonical string identity: `sync_id` first, raw `id` as fallback.
    public var idString: String { syncID ?? id.value }

    public var memoryObservation: MemoryObservation {
        MemoryObservation(
            id: idString,
            title: title,
            content: content,
            project: project,
            tags: tags,
            createdAt: createdAt
        )
    }
}

/// Engram `id` accepts either a JSON Int or String.
public enum EngramID: Decodable, Hashable, Sendable {
    case int(Int)
    case string(String)

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let intValue = try? container.decode(Int.self) {
            self = .int(intValue)
        } else {
            self = .string(try container.decode(String.self))
        }
    }

    public var value: String {
        switch self {
        case .int(let intValue): return String(intValue)
        case .string(let stringValue): return stringValue
        }
    }
}
