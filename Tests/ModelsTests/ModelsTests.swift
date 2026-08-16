import Foundation
import XCTest
@testable import AllInGentleKit

final class ModelsTests: XCTestCase {
    // MARK: - Codable round-trips

    func testProjectCodableRoundTrip() throws {
        let project = Project(
            id: "p1",
            name: "Test Project",
            path: "/Users/test/project",
            source: .engram,
            lastModified: wholeSeconds(Date())
        )
        let decoded = try decodeRoundTrip(project)
        var normalized = decoded
        normalized.lastModified = decoded.lastModified.map(wholeSeconds)
        XCTAssertEqual(project, normalized)
    }

    func testProjectCodableRoundTripNilLastModified() throws {
        let project = Project(
            id: "p2",
            name: "Nil Date Project",
            path: "/Users/test/nil-date",
            source: .codegraph,
            lastModified: nil
        )
        XCTAssertEqual(try decodeRoundTrip(project), project)
    }

    func testMemoryObservationCodableRoundTrip() throws {
        let observation = MemoryObservation(
            id: "m1",
            title: "Memory",
            content: "Content",
            project: "p1",
            tags: ["tag1", "tag2"],
            createdAt: wholeSeconds(Date())
        )
        let decoded = try decodeRoundTrip(observation)
        var normalized = decoded
        normalized.createdAt = wholeSeconds(decoded.createdAt)
        XCTAssertEqual(observation, normalized)
    }

    func testServiceStatusCodableRoundTrip() throws {
        let status = ServiceStatus(
            id: "s1",
            name: "engram serve",
            isRunning: true,
            pid: 1234,
            port: 7437,
            uptime: 3600.5,
            lastError: "boom"
        )
        XCTAssertEqual(try decodeRoundTrip(status), status)
    }

    func testServiceStatusCodableRoundTripNilOptionals() throws {
        let status = ServiceStatus(
            id: "s2",
            name: "codegraph",
            isRunning: false
        )
        XCTAssertEqual(try decodeRoundTrip(status), status)
    }

    func testTokenUsageCodableRoundTrip() throws {
        let usage = TokenUsage(
            id: "t1",
            project: "p1",
            session: "sess1",
            promptTokens: 100,
            completionTokens: 50,
            estimatedCost: 0.012,
            timestamp: wholeSeconds(Date()),
            rawTimeUpdated: 1_800_000.25
        )
        let decoded = try decodeRoundTrip(usage)
        var normalized = decoded
        normalized.timestamp = wholeSeconds(decoded.timestamp)
        XCTAssertEqual(usage, normalized)
    }

    func testSessionSummaryCodableRoundTrip() throws {
        let summary = SessionSummary(
            id: "ss1",
            project: "p1",
            sessionName: "Session A",
            messageCount: 10,
            totalTokens: 1000,
            estimatedCost: 0.05,
            latestDate: wholeSeconds(Date())
        )
        let decoded = try decodeRoundTrip(summary)
        var normalized = decoded
        normalized.latestDate = wholeSeconds(decoded.latestDate)
        XCTAssertEqual(summary, normalized)
    }

    func testChatMessageCodableRoundTrip() throws {
        let message = ChatMessage(
            id: "c1",
            role: .user,
            content: "Hello",
            timestamp: wholeSeconds(Date())
        )
        let decoded = try decodeRoundTrip(message)
        var normalized = decoded
        normalized.timestamp = wholeSeconds(decoded.timestamp)
        XCTAssertEqual(message, normalized)
    }

    // MARK: - Computed properties

    func testTokenUsageTotalTokensComputed() {
        let usage = TokenUsage(
            id: "t1",
            project: "p1",
            promptTokens: 100,
            completionTokens: 50,
            estimatedCost: 0.0
        )
        XCTAssertEqual(usage.totalTokens, 150)
    }

    func testTokenUsageTotalTokensZero() {
        let usage = TokenUsage(
            id: "t2",
            project: "p2",
            promptTokens: 0,
            completionTokens: 0,
            estimatedCost: 0.0
        )
        XCTAssertEqual(usage.totalTokens, 0)
    }

    // MARK: - InteractionState catalog keys

    func testInteractionStateCatalogKeyMapping() {
        let expectations: [(InteractionState, String)] = [
            (.live, "badge.live"),
            (.placeholder, "badge.placeholder"),
            (.disabled, "badge.disabled"),
        ]
        for (state, key) in expectations {
            XCTAssertEqual(state.catalogKey, key)
        }
    }

    func testInteractionStateCatalogKeysUnique() {
        let keys = InteractionState.allCases.map(\.catalogKey)
        XCTAssertEqual(Set(keys).count, 3)
    }

    // MARK: - AllInGentleError Equatable

    func testAllInGentleErrorEquatableEqual() {
        XCTAssertEqual(AllInGentleError.sourceUnavailable("a"), .sourceUnavailable("a"))
    }

    func testAllInGentleErrorEquatableNotEqual() {
        XCTAssertNotEqual(AllInGentleError.sourceUnavailable("a"), .sourceUnavailable("b"))
        XCTAssertNotEqual(AllInGentleError.readOnlyViolation, .sourceUnavailable("a"))
    }

    // MARK: - Sendable compile-time gate

    func testAllModelsConformToSendable() {
        assertSendable(Project(id: "p1", name: "N", path: "/p", source: .engram, lastModified: wholeSeconds(Date())))
        assertSendable(MemoryObservation(id: "m1", title: "T", content: "C", createdAt: wholeSeconds(Date())))
        assertSendable(ServiceStatus(id: "s1", name: "svc", isRunning: true))
        assertSendable(TokenUsage(id: "t1", project: "p1", promptTokens: 1, completionTokens: 2, estimatedCost: 0.0))
        assertSendable(
            SessionSummary(
                id: "ss1", project: "p1", sessionName: "S", messageCount: 1, totalTokens: 2, estimatedCost: 0.0))
        assertSendable(ChatMessage(id: "c1", role: .user, content: "hi"))
        assertSendable(InteractionState.live)
        assertSendable(AllInGentleError.sourceUnavailable("gate"))
    }

    // MARK: - Helpers

    // MARK: - AllInGentleError localization (F3)

    func testReadOnlyViolationLocalizedDescriptionMatchesCatalog() {
        XCTAssertEqual(
            AllInGentleError.readOnlyViolation.localizedDescription,
            L("errors.readOnlyViolation")
        )
    }

    func testSourceUnavailableLocalizedDescriptionMatchesCatalog() {
        XCTAssertEqual(
            AllInGentleError.sourceUnavailable("detail").localizedDescription,
            L("errors.sourceUnavailable", "detail")
        )
    }

    func testInvalidConfigurationLocalizedDescriptionMatchesCatalog() {
        XCTAssertEqual(
            AllInGentleError.invalidConfiguration("detail").localizedDescription,
            L("errors.invalidConfiguration", "detail")
        )
    }

    func testPersistenceFailureLocalizedDescriptionMatchesCatalog() {
        XCTAssertEqual(
            AllInGentleError.persistenceFailure("detail").localizedDescription,
            L("errors.persistenceFailure", "detail")
        )
    }

    func testErrorPayloadDetailSurvivesInterpolation() {
        let message = AllInGentleError.sourceUnavailable("Engram search failed").localizedDescription
        XCTAssertTrue(
            message.contains("Engram search failed"),
            "Payload detail must survive interpolation, got: \(message)"
        )
    }

    func testErrorDescriptionsAreNonEmpty() {
        XCTAssertFalse(AllInGentleError.sourceUnavailable("").localizedDescription.isEmpty)
        XCTAssertFalse(AllInGentleError.readOnlyViolation.localizedDescription.isEmpty)
    }

    func testErrorCatalogKeysPresentInBothLanguages() throws {
        let bundle = try XCTUnwrap(allInGentleKitBundle(), "AllInGentleKit resource bundle not found")
        let en = try XCTUnwrap(catalog(for: "en", in: bundle), "en.lproj catalog not found")
        let es = try XCTUnwrap(catalog(for: "es", in: bundle), "es.lproj catalog not found")

        XCTAssertEqual(en["errors.readOnlyViolation"], "This action is read-only and cannot be performed.")
        XCTAssertEqual(en["errors.sourceUnavailable"], "A data source is unavailable: %@")
        XCTAssertEqual(en["errors.invalidConfiguration"], "Invalid configuration: %@")
        XCTAssertEqual(en["errors.persistenceFailure"], "Could not save your data: %@")

        XCTAssertEqual(es["errors.readOnlyViolation"], "Esta acción es de solo lectura y no se puede realizar.")
        XCTAssertEqual(es["errors.sourceUnavailable"], "Una fuente de datos no está disponible: %@")
        XCTAssertEqual(es["errors.invalidConfiguration"], "Configuración inválida: %@")
        XCTAssertEqual(es["errors.persistenceFailure"], "No se pudieron guardar tus datos: %@")
    }

    func testErrorCatalogKeySetsAreIdenticalAcrossLanguages() throws {
        let bundle = try XCTUnwrap(allInGentleKitBundle(), "AllInGentleKit resource bundle not found")
        let en = try XCTUnwrap(catalog(for: "en", in: bundle), "en.lproj catalog not found")
        let es = try XCTUnwrap(catalog(for: "es", in: bundle), "es.lproj catalog not found")

        XCTAssertEqual(Set(en.keys), Set(es.keys))
        XCTAssertEqual(en.count, 157)
        XCTAssertEqual(es.count, 157)
    }

    // MARK: - Helpers (F3)

    private func allInGentleKitBundle() -> Bundle? {
        var candidates: [Bundle] = [Bundle.module]
        candidates.append(contentsOf: Bundle.allBundles)
        return candidates.first(where: {
            $0.url(forResource: "Localizable", withExtension: "strings", subdirectory: "en.lproj") != nil
        })
    }

    private func catalog(for language: String, in bundle: Bundle) -> [String: String]? {
        guard let url = bundle.url(forResource: "Localizable", withExtension: "strings", subdirectory: "\(language).lproj")
        else { return nil }
        return NSDictionary(contentsOf: url) as? [String: String]
    }

    private func assertSendable<T: Sendable>(_ value: T) {}

    private func wholeSeconds(_ date: Date) -> Date {
        Date(timeIntervalSinceReferenceDate: floor(date.timeIntervalSinceReferenceDate))
    }

    private func decodeRoundTrip<T: Codable>(_ value: T) throws -> T {
        try JSONDecoder().decode(T.self, from: JSONEncoder().encode(value))
    }
}
