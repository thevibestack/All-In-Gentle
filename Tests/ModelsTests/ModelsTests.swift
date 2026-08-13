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

    private func assertSendable<T: Sendable>(_ value: T) {}
}
