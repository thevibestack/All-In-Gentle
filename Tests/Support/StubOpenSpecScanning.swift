import Foundation
import AllInGentleKit

/// In-memory `OpenSpecScanning` double returning injected documents and
/// preview text.
public struct StubOpenSpecScanning: OpenSpecScanning {
    public var documents: [OpenSpecScanner.Document] = []
    public var preview: String = ""

    public init(documents: [OpenSpecScanner.Document] = [], preview: String = "") {
        self.documents = documents
        self.preview = preview
    }

    public func scan(root: String) async throws -> [OpenSpecScanner.Document] {
        documents
    }

    public func preview(at path: String) async throws -> String {
        preview
    }
}
