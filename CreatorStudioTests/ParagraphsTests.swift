import XCTest
@testable import CreatorStudio

final class ParagraphsTests: XCTestCase {
    func testSplitsByBlankLines() {
        let text = "Хук\n\nСхема первая строка\nвторая строка\n\n\nВывод"
        XCTAssertEqual(Paragraphs.split(text), ["Хук", "Схема первая строка\nвторая строка", "Вывод"])
    }

    func testFallsBackToLines() {
        XCTAssertEqual(Paragraphs.split("Один\nДва\nТри"), ["Один", "Два", "Три"])
    }

    func testSingleParagraph() {
        XCTAssertEqual(Paragraphs.split("  Только одно  "), ["Только одно"])
    }

    func testEmptyText() {
        XCTAssertEqual(Paragraphs.split("  \n\n "), [])
    }

    func testWindowsLineEndings() {
        XCTAssertEqual(Paragraphs.split("А\r\n\r\nБ"), ["А", "Б"])
    }

    func testClamp() {
        XCTAssertEqual(Paragraphs.clamp(-1, count: 3), 0)
        XCTAssertEqual(Paragraphs.clamp(5, count: 3), 2)
        XCTAssertEqual(Paragraphs.clamp(1, count: 0), 0)
    }
}
