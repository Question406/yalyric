// Sources/Display/FrameAnimator.swift
import AppKit
import QuartzCore

/// Animates a window frame with explicit ownership of the in-flight animation.
///
/// `NSWindow.animator().setFrame` does not compose: a second call while the
/// first is still running can leave the window with one target's origin and
/// the other's size. Here every `animate` restarts from the frame the caller
/// passes in (normally the window's current frame) and replaces whatever was
/// running, so the final frame is always the last target and every
/// intermediate frame is a straight interpolation between two known rects.
final class FrameAnimator {
    private let apply: (NSRect) -> Void
    private var start = NSRect.zero
    private var end = NSRect.zero
    private var startTime: TimeInterval = 0
    private var duration: TimeInterval = 0
    private var timer: Timer?

    private(set) var isAnimating = false
    /// Called once when an animation reaches its target (not when cancelled).
    var onComplete: (() -> Void)?

    init(apply: @escaping (NSRect) -> Void) {
        self.apply = apply
    }

    deinit { timer?.invalidate() }

    func animate(from current: NSRect, to target: NSRect, duration: TimeInterval, now: TimeInterval = CACurrentMediaTime()) {
        cancel()
        start = current
        end = target
        startTime = now
        self.duration = max(0, duration)
        isAnimating = true
        if self.duration == 0 {
            step(now: now)
            return
        }
        let t = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.step(now: CACurrentMediaTime())
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    /// Stops the animation where it is. The frame applied so far stays.
    func cancel() {
        timer?.invalidate()
        timer = nil
        isAnimating = false
    }

    /// Advances to `now` and applies the interpolated frame. Exposed for tests;
    /// the timer calls it on the main run loop.
    func step(now: TimeInterval) {
        guard isAnimating else { return }
        let raw = duration > 0 ? (now - startTime) / duration : 1
        let progress = min(1, max(0, raw))
        let eased = Self.easeInOut(progress)
        apply(Self.lerp(start, end, eased))
        if progress >= 1 {
            cancel()
            onComplete?()
        }
    }

    private static func easeInOut(_ t: Double) -> Double {
        t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2
    }

    private static func lerp(_ a: NSRect, _ b: NSRect, _ t: Double) -> NSRect {
        let k = CGFloat(t)
        return NSRect(x: a.minX + (b.minX - a.minX) * k,
                      y: a.minY + (b.minY - a.minY) * k,
                      width: a.width + (b.width - a.width) * k,
                      height: a.height + (b.height - a.height) * k)
    }
}
