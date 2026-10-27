import XCTest
import CoreMedia
@testable import CreatorStudio

final class PausableTimelineTests: XCTestCase {
    private func t(_ s: Double) -> CMTime { CMTime(seconds: s, preferredTimescale: 600) }

    func testWithoutPausePassesThrough() {
        var tl = PausableTimeline()
        XCTAssertEqual(tl.map(presentation: t(1), duration: .invalid), t(1))
        XCTAssertEqual(tl.map(presentation: t(2), duration: .invalid), t(2))
    }

    func testPausedSamplesAreDropped() {
        var tl = PausableTimeline()
        _ = tl.map(presentation: t(1), duration: .invalid)
        tl.pause()
        XCTAssertNil(tl.map(presentation: t(2), duration: .invalid))
    }

    func testPauseGapIsRemoved() {
        var tl = PausableTimeline()
        _ = tl.map(presentation: t(1), duration: .invalid)
        _ = tl.map(presentation: t(2), duration: .invalid)
        tl.pause()
        _ = tl.map(presentation: t(5), duration: .invalid)
        tl.resume()
        // Пауза 2 → 10 секунд: в файле время продолжается с 2.
        XCTAssertEqual(tl.map(presentation: t(10), duration: .invalid), t(2))
        XCTAssertEqual(tl.map(presentation: t(11), duration: .invalid), t(3))
    }

    func testTwoPausesAccumulate() {
        var tl = PausableTimeline()
        _ = tl.map(presentation: t(1), duration: .invalid)
        tl.pause(); tl.resume()
        _ = tl.map(presentation: t(4), duration: .invalid) // офсет 3
        tl.pause(); tl.resume()
        XCTAssertEqual(tl.map(presentation: t(10), duration: .invalid), t(1)) // офсет 9
        XCTAssertEqual(tl.offset, t(9))
    }

    func testAudioDurationCountsTowardsLastEnd() {
        var tl = PausableTimeline()
        _ = tl.map(presentation: t(1), duration: t(0.5))
        tl.pause(); tl.resume()
        XCTAssertEqual(tl.map(presentation: t(3), duration: t(0.5)), t(1.5))
    }

    func testDoublePauseAndResumeAreIdempotent() {
        var tl = PausableTimeline()
        tl.pause(); tl.pause()
        XCTAssertTrue(tl.isPaused)
        tl.resume(); tl.resume()
        XCTAssertFalse(tl.isPaused)
    }
}
