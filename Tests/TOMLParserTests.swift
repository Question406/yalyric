import XCTest
@testable import yalyricLib

final class TOMLParserTests: XCTestCase {

    func testParseBasicTypes() {
        let toml = """
        name = "yalyric"
        version = 42
        pi = 3.14
        enabled = true
        disabled = false
        """
        let result = TOMLParser.parse(toml)
        let root = result[""] ?? [:]
        XCTAssertEqual(root["name"] as? String, "yalyric")
        XCTAssertEqual(root["version"] as? Int, 42)
        XCTAssertEqual(root["pi"] as? Double, 3.14)
        XCTAssertEqual(root["enabled"] as? Bool, true)
        XCTAssertEqual(root["disabled"] as? Bool, false)
    }

    func testParseSections() {
        let toml = """
        [general]
        offset = 1.5

        [theme]
        fontName = "Menlo"
        fontSize = 24
        """
        let result = TOMLParser.parse(toml)
        XCTAssertEqual(result["general"]?["offset"] as? Double, 1.5)
        XCTAssertEqual(result["theme"]?["fontName"] as? String, "Menlo")
        XCTAssertEqual(result["theme"]?["fontSize"] as? Int, 24)
    }

    func testParseComments() {
        let toml = """
        # This is a comment
        key = "value"  # inline comment
        number = 10 # another comment
        """
        let result = TOMLParser.parse(toml)
        let root = result[""] ?? [:]
        XCTAssertEqual(root["key"] as? String, "value")
        XCTAssertEqual(root["number"] as? Int, 10)
    }

    func testParseEmptyAndBlankLines() {
        let toml = """

        key = "value"

        [section]

        other = true

        """
        let result = TOMLParser.parse(toml)
        XCTAssertEqual(result[""]?["key"] as? String, "value")
        XCTAssertEqual(result["section"]?["other"] as? Bool, true)
    }

    func testParseSpacingVariations() {
        let toml = """
        a=1
        b = 2
        c =3
        d= 4
        """
        let result = TOMLParser.parse(toml)
        let root = result[""] ?? [:]
        XCTAssertEqual(root["a"] as? Int, 1)
        XCTAssertEqual(root["b"] as? Int, 2)
        XCTAssertEqual(root["c"] as? Int, 3)
        XCTAssertEqual(root["d"] as? Int, 4)
    }

    func testSerializeRoundTrip() {
        let data: [String: [String: Any]] = [
            "general": [
                "enabled": true,
                "delay": 3.0,
            ],
            "theme": [
                "font": "Menlo",
                "size": 24,
            ]
        ]
        let text = TOMLParser.serialize(data)
        let parsed = TOMLParser.parse(text)

        XCTAssertEqual(parsed["general"]?["enabled"] as? Bool, true)
        XCTAssertEqual(parsed["general"]?["delay"] as? Double, 3.0)
        XCTAssertEqual(parsed["theme"]?["font"] as? String, "Menlo")
        XCTAssertEqual(parsed["theme"]?["size"] as? Int, 24)
    }

    func testParseEmptyString() {
        let result = TOMLParser.parse("")
        XCTAssertTrue(result.isEmpty)
    }

    func testParseQuotedStringWithHash() {
        let toml = """
        color = "#ff0000"
        """
        let result = TOMLParser.parse(toml)
        XCTAssertEqual(result[""]?["color"] as? String, "#ff0000")
    }
}
