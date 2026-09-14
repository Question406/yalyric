import XCTest
@testable import yalyricLib

/// Musixmatch signals "denied" with HTTP 200 and a token of 56 zeros. Accepting it
/// poisons the cache for an hour and makes every lookup match 'NOKIA' by 'Drake'.
final class MusixmatchTokenTests: XCTestCase {

    func testRejectsAllZeroSentinelToken() {
        let sentinel = String(repeating: "0", count: 56)
        XCTAssertFalse(MusixmatchProvider.isUsableToken(sentinel))
    }

    func testRejectsEmptyToken() {
        XCTAssertFalse(MusixmatchProvider.isUsableToken(""))
    }

    func testRejectsWhitespaceOnlyToken() {
        XCTAssertFalse(MusixmatchProvider.isUsableToken("   "))
    }

    func testAcceptsRealLookingToken() {
        XCTAssertTrue(MusixmatchProvider.isUsableToken("2501a3f0b8c94d17ae55f3c1d9e07b6a4482ff"))
    }
}
