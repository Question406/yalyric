import XCTest
@testable import yalyricLib

/// A persisted `providerOrder` shadows the default list, so a newly added provider
/// would be invisible to any user who had ever reordered providers in Settings.
final class ProviderRegistryTests: XCTestCase {

    func testAppendsNewlyAddedProviderToSavedOrder() {
        let saved = ["netease", "lrclib", "spotify", "musixmatch"]   // saved before kugou existed
        let merged = AppConfig.mergedProviderOrder(saved: saved, known: AppConfig.Sources.knownProviders)
        XCTAssertTrue(merged.contains("kugou"), "new provider must appear for existing users")
        XCTAssertEqual(Array(merged.prefix(4)), saved, "user's ordering must be preserved")
    }

    func testDropsProvidersThatNoLongerExist() {
        let merged = AppConfig.mergedProviderOrder(saved: ["lrclib", "obsolete"], known: ["lrclib", "kugou"])
        XCTAssertEqual(merged, ["lrclib", "kugou"])
    }

    func testEmptySavedOrderFallsBackToKnownOrder() {
        let merged = AppConfig.mergedProviderOrder(saved: [], known: ["lrclib", "kugou"])
        XCTAssertEqual(merged, ["lrclib", "kugou"])
    }

    func testDeduplicatesRepeatedEntries() {
        let merged = AppConfig.mergedProviderOrder(saved: ["lrclib", "lrclib"], known: ["lrclib", "kugou"])
        XCTAssertEqual(merged, ["lrclib", "kugou"])
    }

    func testKugouIsRegisteredEverywhere() {
        XCTAssertTrue(AppConfig.Sources.knownProviders.contains("kugou"))
        XCTAssertTrue(AppConfig.Sources.providerOrder.defaultValue.contains("kugou"))
    }
}
