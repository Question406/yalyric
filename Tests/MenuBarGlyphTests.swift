import XCTest
import AppKit
@testable import yalyricLib

/// The status-bar icon is drawn in code rather than shipped as a file, so `swift build`
/// runs show it too. It must stay a template image, or it won't adapt to dark menu bars.
final class MenuBarGlyphTests: XCTestCase {

    func testGlyphIsAnEighteenPointTemplateImage() {
        let image = MenuBarGlyph.image()
        XCTAssertTrue(image.isTemplate)
        XCTAssertEqual(image.size, NSSize(width: 18, height: 18))
    }

    func testGlyphDrawsTheNoteSolidAndTheUnsungLineFaint() throws {
        let rep = try XCTUnwrap(rasterize(MenuBarGlyph.image(), scale: 2))
        // Pixel rows are top-down; the icon is 36×36 px at 2×.
        let noteHead = rep.colorAt(x: 7, y: 19)!.alphaComponent
        let sungLine = rep.colorAt(x: 10, y: 30)!.alphaComponent
        let unsungLine = rep.colorAt(x: 28, y: 30)!.alphaComponent
        let empty = rep.colorAt(x: 30, y: 4)!.alphaComponent
        XCTAssertGreaterThan(noteHead, 0.9)
        XCTAssertGreaterThan(sungLine, 0.9)
        XCTAssertEqual(unsungLine, 0.35, accuracy: 0.05)
        XCTAssertEqual(empty, 0, accuracy: 0.01)
    }

    private func rasterize(_ image: NSImage, scale: Int) -> NSBitmapImageRep? {
        let px = Int(image.size.width) * scale
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        rep.size = image.size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(origin: .zero, size: image.size))
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }
}
