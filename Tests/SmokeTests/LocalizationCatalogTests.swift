import Foundation
import XCTest
@testable import AllInGentleKit

/// Catalog consistency for the en and es Localizable.strings files
/// (spec domain `localization`, R3.1/R3.3).
final class LocalizationCatalogTests: XCTestCase {

    // MARK: - R3.1 fallback key present

    func testFallbackKeyPresentInBothCatalogs() throws {
        let en = try catalog(for: "en")
        let es = try catalog(for: "es")

        XCTAssertNotNil(
            en["projectDetail.memories.fallback"], "en catalog must contain projectDetail.memories.fallback")
        XCTAssertNotNil(
            es["projectDetail.memories.fallback"], "es catalog must contain projectDetail.memories.fallback")
    }

    func testFallbackKeyIsTranslatedNotTheRawKey() throws {
        let en = try catalog(for: "en")
        let es = try catalog(for: "es")

        XCTAssertEqual(
            en["projectDetail.memories.fallback"],
            "Showing results from a broader search"
        )
        XCTAssertEqual(
            es["projectDetail.memories.fallback"],
            "Mostrando resultados de una búsqueda más amplia"
        )
    }

    // MARK: - R3.3 catalog consistency

    func testEnglishAndSpanishCatalogsStayInSync() throws {
        let en = try catalog(for: "en")
        let es = try catalog(for: "es")

        XCTAssertEqual(Set(en.keys), Set(es.keys), "en and es catalogs must define the same keys")
        XCTAssertEqual(en.count, 160, "en catalog must keep 160 keys")
        XCTAssertEqual(es.count, 160, "es catalog must keep 160 keys")
    }

    // MARK: - Helpers

    private enum CatalogError: Error {
        case bundleNotFound
        case catalogMissing(String)
        case unparseable(String)
    }

    private func catalog(for language: String) throws -> [String: String] {
        let bundle = try catalogBundle()
        guard
            let url = bundle.url(
                forResource: "Localizable",
                withExtension: "strings",
                subdirectory: "\(language).lproj"
            )
        else {
            throw CatalogError.catalogMissing("\(language).lproj/Localizable.strings")
        }
        guard let dict = NSDictionary(contentsOf: url) as? [String: String] else {
            throw CatalogError.unparseable(url.path)
        }
        return dict
    }

    /// The kit bundle hosts the processed `Resources` folder. In SPM builds
    /// it is a sibling of the test bundle (`All-In-Gentle_AllInGentleKit.bundle`
    /// next to `All-In-GentlePackageTests.xctest`); fall back to scanning
    /// loaded bundles.
    private func catalogBundle() throws -> Bundle {
        let siblingURL = Bundle(for: LocalizationCatalogTests.self)
            .bundleURL
            .deletingLastPathComponent()
            .appendingPathComponent("All-In-Gentle_AllInGentleKit.bundle")
        if let sibling = Bundle(url: siblingURL),
            sibling.url(forResource: "Localizable", withExtension: "strings", subdirectory: "Resources/en.lproj") != nil
        {
            return sibling
        }
        if let found = Bundle.allBundles.first(where: {
            $0.url(forResource: "Localizable", withExtension: "strings", subdirectory: "Resources/en.lproj") != nil
        }) {
            return found
        }
        throw CatalogError.bundleNotFound
    }
}
