import Foundation
import Observation

@MainActor
@Observable
public final class TokensViewModel {
    public private(set) var items: [TokenUsage] = []
    public private(set) var isLoading: Bool = false
    public var errorMessage: String?
    public private(set) var canLoadMore: Bool = false

    private let client: OpenCodeClient
    private let pageSize: Int
    private var nextCursor: TokenCursor?

    public init(client: OpenCodeClient, pageSize: Int = 50) {
        self.client = client
        self.pageSize = pageSize
    }

    public convenience init(openCodeDBPath: String? = nil) {
        let path = Self.resolvePath(openCodeDBPath) ?? Self.defaultOpenCodeDBPath()
        self.init(client: OpenCodeClient(dbPath: path))
    }

    public func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let page = try await client.tokenUsagePage(limit: pageSize)
            items = page
            nextCursor = page.last.flatMap { makeCursor(from: $0) }
            canLoadMore = page.count == pageSize
        } catch {
            errorMessage = error.localizedDescription
            canLoadMore = false
        }
    }

    public func loadNextPage() async {
        guard !isLoading, canLoadMore, nextCursor != nil else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let page = try await client.tokenUsagePage(after: nextCursor, limit: pageSize)
            items.append(contentsOf: page)
            nextCursor = page.last.flatMap { makeCursor(from: $0) }
            canLoadMore = page.count == pageSize
        } catch {
            errorMessage = error.localizedDescription
            canLoadMore = false
        }
    }

    private func makeCursor(from usage: TokenUsage) -> TokenCursor? {
        guard let millis = usage.rawTimeUpdated else { return nil }
        return TokenCursor(timeUpdated: millis, id: usage.id)
    }

    private static func resolvePath(_ path: String?) -> String? {
        guard let path else { return nil }
        return (path as NSString).expandingTildeInPath
    }

    private static func defaultOpenCodeDBPath() -> String {
        FileManager.default.homeDirectoryForCurrentUser.path + "/.local/share/opencode/opencode.db"
    }
}
