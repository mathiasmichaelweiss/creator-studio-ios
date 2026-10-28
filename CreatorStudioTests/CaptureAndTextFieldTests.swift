import XCTest
@testable import CreatorStudio

final class CaptureAndTextFieldTests: XCTestCase {
    func testButtonFiresOnlyOnRelease() {
        XCTAssertFalse(CaptureButtonGate.shouldFire(phase: .began))
        XCTAssertTrue(CaptureButtonGate.shouldFire(phase: .ended))
        XCTAssertFalse(CaptureButtonGate.shouldFire(phase: .cancelled))
    }

    func testTextFieldSplitsByBlankLines() {
        let s = NotionParser.fieldSections("Первый абзац.\n\nВторой\nабзац.\r\n\r\n\n\nТретий.")
        XCTAssertEqual(s.map(\.text), ["Первый абзац.", "Второй\nабзац.", "Третий."])
        XCTAssertTrue(s.allSatisfy { $0.label == nil })
    }

    func testEmptyTextField() {
        XCTAssertTrue(NotionParser.fieldSections("   \n\n ").isEmpty)
    }

    func testScriptTakesTextFieldWhenBodyEmpty() {
        func rt(_ t: String) -> [String: Any] { ["type": "rich_text", "rich_text": [["plain_text": t]]] }
        let page: [String: Any] = [
            "id": "p1",
            "properties": [
                "Название": ["type": "title", "title": [["plain_text": "Врачи"]]],
                "Хук": rt("Хук."),
                "Текст": rt("Часть 1.\n\nЧасть 2."),
                "CTA": rt("Призыв.")
            ]
        ]
        let script = NotionParser.script(page: page)
        XCTAssertEqual(script?.body.sections.map(\.text), ["Часть 1.", "Часть 2."])
    }
}
