import XCTest
@testable import CreatorStudio

/// Инфоповод целиком одной карточкой на экране записи.
final class NewsCardTests: XCTestCase {
    func testWholeCardKeepsAllText() {
        let text = "Первый абзац\n\nВторой абзац\n\nТретий"
        XCTAssertEqual(Paragraphs.cards(text, whole: false).count, 3)
        XCTAssertEqual(Paragraphs.cards(text, whole: true), [text])
        XCTAssertEqual(Paragraphs.cards("  \n ", whole: true), [])
    }

    func testNewsCardText() {
        let n = NewsItem(id: "1", title: "Новый Mindestlohn", summary: "С января больше.", why: "Касается мини-джобов.")
        XCTAssertEqual(n.cardText, "Новый Mindestlohn\n\nС января больше.\n\nПочему важно: Касается мини-джобов.")
        XCTAssertEqual(NewsItem(id: "2", title: "Только заголовок").cardText, "Только заголовок")
    }
}
