import XCTest
@testable import CreatorStudio

final class PrompterMathTests: XCTestCase {
    func testAdvanceIsSpeedTimesTime() {
        XCTAssertEqual(PrompterMath.advance(speed: 40, from: 1.0, to: 1.05), 2, accuracy: 0.0001)
    }

    func testAdvanceClampsLongGaps() {
        // После возврата из фона текст не должен прыгнуть далеко вперёд.
        XCTAssertEqual(PrompterMath.advance(speed: 40, from: 1.0, to: 5.0), 4, accuracy: 0.0001)
    }

    func testAdvanceNeverNegative() {
        XCTAssertEqual(PrompterMath.advance(speed: 40, from: 2.0, to: 1.0), 0)
    }
}
