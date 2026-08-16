import Foundation
import SQLite3
import XCTest
@testable import AllInGentleKit

/// Approval-pin tests for the `TokensViewModel` pagination state machine (F21, PR 5).
///
/// Hermetic by construction: every test seeds a throwaway SQLite database in a temp
/// file, closes the writer, and drives the view model through a read-only
/// `OpenCodeClient` over that file. No live OpenCode database, no services.
@MainActor
final class TokensViewModelPaginationTests: XCTestCase {

    private static let sessionSeed =
        """
        CREATE TABLE session (
            id TEXT PRIMARY KEY,
            project_id TEXT,
            title TEXT,
            cost REAL,
            tokens_input INTEGER,
            tokens_output INTEGER,
            time_updated INTEGER
        );
        """

    /// s3 is newest (3000), s1 oldest (1000): DESC order yields s3, s2, s1.
    private static let threeRowSeed =
        TokensViewModelPaginationTests.sessionSeed
        + "INSERT INTO session VALUES ('s1','all-in-gentle','Auth fix',0.1,10,20,1000);"
        + "INSERT INTO session VALUES ('s2','all-in-gentle','Wiki add',0.2,30,40,2000);"
        + "INSERT INTO session VALUES ('s3','all-in-gentle','Plan',0.3,50,60,3000);"

    /// Creates a hermetic temp database seeded with `seedSQL`, closes the writer,
    /// and returns a view model over a read-only client (F25 temp-DB pattern).
    private func makeViewModel(seedSQL: String, pageSize: Int) -> (viewModel: TokensViewModel, dbURL: URL) {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("db")
        var db: OpaquePointer?
        sqlite3_open(tempURL.path, &db)
        let status = sqlite3_exec(db, seedSQL, nil, nil, nil)
        XCTAssertEqual(status, SQLITE_OK, "Seed SQL must execute cleanly")
        sqlite3_close(db)
        return (TokensViewModel(client: OpenCodeClient(dbPath: tempURL.path), pageSize: pageSize), tempURL)
    }

    private func makeUnopenableClientPath() -> String {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("missing")
            .appendingPathExtension("db")
            .path
    }

    // MARK: - 5.1 load() first page (R-5.1/R-5.2, S-5.1)

    func testLoadReturnsFirstFullPageSetsCanLoadMoreAndKeepsCursorData() async throws {
        let (viewModel, tempURL) = makeViewModel(seedSQL: Self.threeRowSeed, pageSize: 2)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        await viewModel.load()

        XCTAssertEqual(
            viewModel.items.map(\.id), ["s3", "s2"], "First page must be the two newest rows in DESC order")
        XCTAssertEqual(viewModel.items.count, 2)
        XCTAssertTrue(viewModel.canLoadMore, "A full page (count == pageSize) must enable load-more")
        XCTAssertNil(viewModel.errorMessage)
        // Cursor input data: rawTimeUpdated must be materialized so makeCursor can build a keyset cursor.
        XCTAssertEqual(viewModel.items[0].rawTimeUpdated, 3000)
        XCTAssertEqual(viewModel.items[1].rawTimeUpdated, 2000)
        XCTAssertEqual(viewModel.items[0].timestamp, Date(timeIntervalSince1970: 3.0))
        XCTAssertEqual(viewModel.items[0].project, "all-in-gentle")
        XCTAssertEqual(viewModel.items[0].session, "Plan")
        XCTAssertEqual(viewModel.items[0].totalTokens, 110)
    }

    // MARK: - 5.2 loadNextPage() short final page (R-5.2, S-5.2)

    func testLoadNextPageAppendsShortFinalPageAndClearsCanLoadMore() async throws {
        let (viewModel, tempURL) = makeViewModel(seedSQL: Self.threeRowSeed, pageSize: 2)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        await viewModel.load()
        await viewModel.loadNextPage()

        XCTAssertEqual(
            viewModel.items.map(\.id), ["s3", "s2", "s1"], "Second page must append the remaining row")
        XCTAssertEqual(viewModel.items.count, 3)
        XCTAssertFalse(viewModel.canLoadMore, "A short page (count < pageSize) must disable load-more")
        XCTAssertEqual(viewModel.items.last?.session, "Auth fix")
    }

    // MARK: - 5.3 loadNextPage() guard no-ops (R-5.3, S-5.3)

    func testLoadNextPageIsNoOpWhenCanLoadMoreIsFalse() async throws {
        let (viewModel, tempURL) = makeViewModel(seedSQL: Self.threeRowSeed, pageSize: 2)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        await viewModel.load()
        await viewModel.loadNextPage()
        XCTAssertEqual(viewModel.items.count, 3)

        await viewModel.loadNextPage()

        XCTAssertEqual(viewModel.items.count, 3, "After the final page, loadNextPage must be a no-op")
        XCTAssertEqual(viewModel.items.map(\.id), ["s3", "s2", "s1"])
        XCTAssertFalse(viewModel.canLoadMore)
        XCTAssertNil(viewModel.errorMessage, "A guarded no-op must not surface an error")
    }

    func testLoadNextPageIsNoOpWhenNextCursorIsNil() async throws {
        let (viewModel, tempURL) = makeViewModel(seedSQL: Self.threeRowSeed, pageSize: 0)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        await viewModel.load()
        // pageSize 0 -> LIMIT 0 -> empty page -> nextCursor nil, yet the heuristic
        // (count == pageSize -> 0 == 0) still reports canLoadMore. The nil-cursor
        // guard is the only thing stopping a page fetch.
        XCTAssertTrue(viewModel.canLoadMore)
        XCTAssertTrue(viewModel.items.isEmpty)

        await viewModel.loadNextPage()

        XCTAssertTrue(viewModel.items.isEmpty, "nil nextCursor must make loadNextPage a no-op")
        XCTAssertTrue(viewModel.canLoadMore, "Guard no-op must not mutate state")
        XCTAssertNil(viewModel.errorMessage)
    }

    // MARK: - 5.4 error paths (R-5.4, S-5.4)

    func testLoadSetsErrorMessageAndClearsCanLoadMoreOnClientError() async throws {
        let viewModel = TokensViewModel(client: OpenCodeClient(dbPath: makeUnopenableClientPath()), pageSize: 2)

        await viewModel.load()

        XCTAssertTrue(viewModel.items.isEmpty)
        XCTAssertFalse(viewModel.canLoadMore, "Error must clear canLoadMore")
        XCTAssertNotNil(viewModel.errorMessage)
        XCTAssertEqual(
            viewModel.errorMessage,
            AllInGentleError.sourceUnavailable("Unable to open OpenCode database read-only: 14").localizedDescription
        )
    }

    func testLoadNextPageSetsErrorMessageOnClientError() async throws {
        let (viewModel, tempURL) = makeViewModel(seedSQL: Self.threeRowSeed, pageSize: 2)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        await viewModel.load()
        XCTAssertEqual(viewModel.items.count, 2)
        XCTAssertNil(viewModel.errorMessage)

        try FileManager.default.removeItem(at: tempURL)

        await viewModel.loadNextPage()

        XCTAssertEqual(viewModel.items.count, 2, "Failed page fetch must keep previously loaded items")
        XCTAssertFalse(viewModel.canLoadMore, "Error must clear canLoadMore")
        XCTAssertNotNil(viewModel.errorMessage)
    }

    // MARK: - 5.5 filteredItems (R-5.5, S-5.5)

    func testFilteredItemsMatchesProjectCaseInsensitively() async throws {
        let (viewModel, tempURL) = makeViewModel(seedSQL: Self.threeRowSeed, pageSize: 50)
        defer { try? FileManager.default.removeItem(at: tempURL) }
        await viewModel.load()

        viewModel.searchQuery = "ALL-IN"

        XCTAssertEqual(
            viewModel.filteredItems.map(\.id), ["s3", "s2", "s1"], "Project match must be case-insensitive")
    }

    func testFilteredItemsMatchesSessionCaseInsensitivelyAndIgnoresNilSession() async throws {
        let seed =
            Self.threeRowSeed
            + "INSERT INTO session VALUES ('s4','other-project',NULL,0.4,70,80,4000);"
        let (viewModel, tempURL) = makeViewModel(seedSQL: seed, pageSize: 50)
        defer { try? FileManager.default.removeItem(at: tempURL) }
        await viewModel.load()

        viewModel.searchQuery = "AUTH"

        XCTAssertEqual(viewModel.filteredItems.map(\.id), ["s1"], "Session match must be case-insensitive")
        XCTAssertFalse(
            viewModel.filteredItems.contains { $0.id == "s4" },
            "A nil session must never match a session search")

        viewModel.searchQuery = "WIKI"
        XCTAssertEqual(viewModel.filteredItems.map(\.id), ["s2"])
    }

    func testFilteredItemsReturnsEmptyWhenNoRowMatches() async throws {
        let (viewModel, tempURL) = makeViewModel(seedSQL: Self.threeRowSeed, pageSize: 50)
        defer { try? FileManager.default.removeItem(at: tempURL) }
        await viewModel.load()

        viewModel.searchQuery = "zzz"

        // No seeded row contains "zzz" in project or session — the emptiness comes
        // from the filter running over three loaded rows, not from an empty source.
        XCTAssertEqual(viewModel.items.count, 3, "Source is non-empty so the filter decides the result")
        XCTAssertTrue(viewModel.filteredItems.isEmpty)
    }

    func testFilteredItemsReturnsAllItemsWhenQueryIsEmpty() async throws {
        let (viewModel, tempURL) = makeViewModel(seedSQL: Self.threeRowSeed, pageSize: 50)
        defer { try? FileManager.default.removeItem(at: tempURL) }
        await viewModel.load()

        viewModel.searchQuery = ""

        XCTAssertEqual(viewModel.filteredItems.map(\.id), ["s3", "s2", "s1"], "Empty query must bypass filtering")
    }

    // MARK: - Cursor keyset resume with id DESC tie-break (mission bullet)

    func testLoadNextPageResumesKeysetWithIdDescTieBreakOnEqualTimestamps() async throws {
        let seed =
            Self.sessionSeed
            + "INSERT INTO session VALUES ('a','p','A',0.1,1,1,1000);"
            + "INSERT INTO session VALUES ('b','p','B',0.1,1,1,1000);"
            + "INSERT INTO session VALUES ('c','p','C',0.1,1,1,1000);"
        let (viewModel, tempURL) = makeViewModel(seedSQL: seed, pageSize: 2)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        await viewModel.load()
        XCTAssertEqual(viewModel.items.map(\.id), ["c", "b"], "Equal timestamps must tie-break with id DESC")

        await viewModel.loadNextPage()

        XCTAssertEqual(
            viewModel.items.map(\.id), ["c", "b", "a"], "Keyset resume must continue in id DESC order")
        XCTAssertFalse(viewModel.canLoadMore)
    }
}
