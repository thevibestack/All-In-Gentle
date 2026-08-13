import Foundation
import XCTest
@testable import AllInGentleKit

final class LLMServiceTests: XCTestCase {
    func testParseDeepSeekSSEStreamFromFixture() throws {
        guard let url = Bundle.module.url(forResource: "deepseek-stream", withExtension: "txt") else {
            XCTFail("Missing fixture deepseek-stream.txt")
            return
        }

        let text = try String(contentsOf: url, encoding: .utf8)
        let chunks = try text
            .components(separatedBy: .newlines)
            .compactMap { line in
                try DeepSeekSSEParser.parse(line: line)
            }

        XCTAssertEqual(chunks.count, 3, "Fixture should yield three content/finish chunks before [DONE]")
        XCTAssertEqual(chunks[0].textDelta, "Hola")
        XCTAssertNil(chunks[0].finishReason)
        XCTAssertEqual(chunks[1].textDelta, " mundo")
        XCTAssertNil(chunks[1].finishReason)
        XCTAssertNil(chunks[2].textDelta)
        XCTAssertEqual(chunks[2].finishReason, "stop")
    }
}
