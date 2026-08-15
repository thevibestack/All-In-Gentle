import Foundation
import XCTest
@testable import AllInGentleKit

final class ModelsTests: XCTestCase {
    func testProjectConformsToSendable() async {
        let project = Project(
            id: "p1",
            name: "Test Project",
            path: "/Users/test/project",
            source: .engram,
            lastModified: Date()
        )
        assertSendable(project)
        XCTAssertEqual(project.source, .engram)
        XCTAssertEqual(project.name, "Test Project")
    }

    func testMemoryObservationConformsToSendable() async {
        let observation = MemoryObservation(
            id: "m1",
            title: "Memory",
            content: "Content",
            project: "p1",
            tags: ["tag1"]
        )
        assertSendable(observation)
        XCTAssertEqual(observation.tags, ["tag1"])
    }

    func testServiceStatusConformsToSendable() async {
        let status = ServiceStatus(
            id: "s1",
            name: "engram serve",
            isRunning: true,
            pid: 1234,
            port: 7437,
            uptime: 3600
        )
        assertSendable(status)
        XCTAssertEqual(status.port, 7437)
    }

    func testTokenUsageConformsToSendable() async {
        let usage = TokenUsage(
            id: "t1",
            project: "p1",
            session: "sess1",
            promptTokens: 100,
            completionTokens: 50,
            estimatedCost: 0.012
        )
        assertSendable(usage)
        XCTAssertEqual(usage.totalTokens, 150)
    }

    func testSessionSummaryConformsToSendable() async {
        let summary = SessionSummary(
            id: "ss1",
            project: "p1",
            sessionName: "Session A",
            messageCount: 10,
            totalTokens: 1000,
            estimatedCost: 0.05
        )
        assertSendable(summary)
        XCTAssertEqual(summary.messageCount, 10)
    }

    func testChatMessageConformsToSendable() async {
        let message = ChatMessage(
            id: "c1",
            role: .user,
            content: "Hello"
        )
        assertSendable(message)
        XCTAssertEqual(message.role, .user)
    }

    func testInteractionStateIsSendable() async {
        assertSendable(InteractionState.live)
        assertSendable(InteractionState.placeholder)
        assertSendable(InteractionState.disabled)
    }

    func testErrorsAreSendable() async {
        assertSendable(AllInGentleError.readOnlyViolation)
        assertSendable(AllInGentleError.sourceUnavailable("test"))
    }

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
}
