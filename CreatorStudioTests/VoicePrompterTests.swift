import XCTest
@testable import CreatorStudio

/// Суфлёр по голосу: поиск места в сценарии, плавный подъезд, положение строки.
final class ScriptAlignerTests: XCTestCase {
    private let text = "Мой коллега получает больше меня. А ездит на старом Гольфе, обедает бутербродом из дома. " +
        "У нас бы его назвали нищебродом. А я думал, что немцы очень жадные."

    func testFollowsGrowingTranscript() {
        var a = ScriptAligner(text: text)
        XCTAssertEqual(a.consume(transcript: "мой"), 0)
        XCTAssertEqual(a.consume(transcript: "мой коллега"), 1)
        XCTAssertEqual(a.consume(transcript: "мой коллега получает больше меня"), 4)
        XCTAssertEqual(a.consume(transcript: "мой коллега получает больше меня а ездит на старом гольфе"), 9)
        XCTAssertNil(a.consume(transcript: "мой коллега получает больше меня а ездит на старом гольфе"), "без новых слов место не двигается")
    }

    func testSkippedPartJumpsForward() {
        var a = ScriptAligner(text: text)
        XCTAssertEqual(a.consume(transcript: "у нас бы его назвали"), 18)
        XCTAssertEqual(a.position, 19)
    }

    func testCaseEndingsAndYo() {
        var a = ScriptAligner(text: "Её коллеги получают больше")
        XCTAssertEqual(a.consume(transcript: "ее коллегам получала"), 2, "падежи и ё не мешают")
    }

    func testUnrelatedSpeechDoesNotMove() {
        var a = ScriptAligner(text: text)
        XCTAssertNil(a.consume(transcript: "так подожди сейчас начну"))
        XCTAssertEqual(a.position, 0)
        XCTAssertNil(a.consume(transcript: ""))
    }

    func testRepeatedPhraseGoesBackALittle() {
        var a = ScriptAligner(text: text)
        _ = a.consume(transcript: "мой коллега получает больше меня а ездит")
        XCTAssertEqual(a.position, 7)
        XCTAssertEqual(a.consume(transcript: "ой ещё раз больше меня"), 4)
    }

    func testResetAndLocations() {
        var a = ScriptAligner(text: "Привет, мир")
        XCTAssertEqual(a.words.map(\.norm), ["привет", "мир"])
        XCTAssertEqual(a.words.map(\.location), [0, 8])
        _ = a.consume(transcript: "привет мир")
        a.reset()
        XCTAssertEqual(a.position, 0)
    }

    func testSameAndDistance() {
        XCTAssertTrue(ScriptAligner.same("немцы", "немцы"))
        XCTAssertTrue(ScriptAligner.same("бутербродом", "бутерброд"))
        XCTAssertTrue(ScriptAligner.same("гольфе", "гольве"))
        XCTAssertFalse(ScriptAligner.same("дом", "дым"))
        XCTAssertEqual(ScriptAligner.distance("кот", "кит"), 1)
        XCTAssertEqual(ScriptAligner.distance("", "абв"), 3)
    }

    func testEaseMovesPartway() {
        XCTAssertEqual(PrompterMath.ease(current: 0, target: 100, t0: 0, t1: 0.1), 50, accuracy: 0.001)
        XCTAssertEqual(PrompterMath.ease(current: 0, target: 100, t0: 0, t1: 5), 50, accuracy: 0.001, "скачок после фона ограничен")
        XCTAssertEqual(PrompterMath.ease(current: 80, target: 40, t0: 0, t1: 0.05), -10, accuracy: 0.001)
    }

    func testLayoutLineTopGrowsDownTheText() {
        let t = String(repeating: "слово ", count: 60) + "конец"
        let loc = (t as NSString).range(of: "конец").location
        let first = PrompterLayout.lineTop(of: 0, in: t, fontSize: 30, lineSpacing: 7.5, width: 200)
        let last = PrompterLayout.lineTop(of: loc, in: t, fontSize: 30, lineSpacing: 7.5, width: 200)
        XCTAssertEqual(first, 0, accuracy: 0.5)
        XCTAssertGreaterThan(last, 300)
        XCTAssertEqual(PrompterLayout.lineTop(of: 5, in: "", fontSize: 30, lineSpacing: 0, width: 200), 0)
        XCTAssertEqual(PrompterLayout.lineTop(of: 999, in: "a", fontSize: 30, lineSpacing: 0, width: 0), 0)
    }

    func testScrollModeTitles() {
        XCTAssertEqual(ScrollMode.allCases.map(\.title), ["По скорости", "По голосу"])
    }
}
