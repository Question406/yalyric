import XCTest
@testable import yalyricLib

/// `NSWindow.animator().setFrame` does not compose: a second resize issued while
/// one is in flight left the overlay with the first target's origin and the
/// second target's width, 20pt off centre. The overlay now drives its own
/// frame animation, which restarts from the current frame on every retarget.
final class FrameAnimatorTests: XCTestCase {

    private let a = NSRect(x: 1180, y: 0, width: 200, height: 90)    // centre 1280
    private let b = NSRect(x: 1147.5, y: 0, width: 265, height: 90)  // centre 1280
    private let c = NSRect(x: 1159, y: 0, width: 242, height: 90)    // centre 1280

    func testRetargetingMidAnimationKeepsCentreAndEndsAtNewTarget() {
        var applied: [NSRect] = []
        let anim = FrameAnimator { applied.append($0) }

        anim.animate(from: a, to: b, duration: 1, now: 0)
        anim.step(now: 0.5)
        let mid = applied.last!
        XCTAssertGreaterThan(mid.width, a.width)
        XCTAssertLessThan(mid.width, b.width)

        anim.animate(from: mid, to: c, duration: 1, now: 0.5)
        anim.step(now: 1.0)
        anim.step(now: 1.6)

        XCTAssertEqual(applied.last, c)
        for f in applied {
            XCTAssertEqual(f.midX, 1280, accuracy: 0.01, "every intermediate frame must stay centred")
        }
    }

    func testCompletesOnceAndReportsIdle() {
        var completions = 0
        let anim = FrameAnimator { _ in }
        anim.onComplete = { completions += 1 }
        anim.animate(from: a, to: b, duration: 0.3, now: 10)
        XCTAssertTrue(anim.isAnimating)
        anim.step(now: 10.2)
        XCTAssertTrue(anim.isAnimating)
        anim.step(now: 10.4)
        XCTAssertFalse(anim.isAnimating)
        anim.step(now: 10.5)
        XCTAssertEqual(completions, 1)
    }

    func testCancelStopsWithoutApplyingFurtherFrames() {
        var applied: [NSRect] = []
        let anim = FrameAnimator { applied.append($0) }
        anim.animate(from: a, to: b, duration: 1, now: 0)
        anim.step(now: 0.2)
        let count = applied.count
        anim.cancel()
        anim.step(now: 0.8)
        XCTAssertEqual(applied.count, count)
        XCTAssertFalse(anim.isAnimating)
    }
}
