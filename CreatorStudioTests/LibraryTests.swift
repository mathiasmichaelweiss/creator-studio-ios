import XCTest
@testable import CreatorStudio

/// Папки, фильтр по статусу, оценка и провокационная версия.
final class LibraryTests: XCTestCase {
    private func s(_ id: String, type: String, status: String = "Идея",
                   forecast: Forecast? = nil, variants: [ScriptVariant] = []) -> Script {
        Script(id: id, title: id, type: type, status: status, studioId: "", body: ScriptBody(),
               variants: variants, forecast: forecast)
    }

    func testFoldersByType() {
        XCTAssertEqual(ScriptFolder.of(type: "Рилс"), .reels)
        XCTAssertEqual(ScriptFolder.of(type: " карусель "), .carousels)
        XCTAssertEqual(ScriptFolder.of(type: "Формат"), .formats)
        XCTAssertEqual(ScriptFolder.of(type: "Сторис"), .other)
        XCTAssertEqual(ScriptFolder.of(type: ""), .other)
        let all = [s("1", type: "Рилс"), s("2", type: "Карусель"), s("3", type: "Рилс")]
        XCTAssertEqual(ScriptFolder.reels.items(all).map(\.id), ["1", "3"])
        XCTAssertEqual(ScriptFolder.visible(all), [.reels, .carousels, .formats])
        XCTAssertEqual(ScriptFolder.visible(all + [s("4", type: "Сторис")]).last, .other)
    }

    func testAllStatuses() {
        let all = ["Идея", "В работе", "Готов к съёмке", "Снято", "Опубликовано"]
            .enumerated().map { s("\($0.offset)", type: "Рилс", status: $0.element) }
        XCTAssertEqual(StatusFilter.all.count(all), 5)
        XCTAssertEqual(StatusFilter.inWork.apply(all).map(\.id), ["1"])
        XCTAssertEqual(StatusFilter.ready.apply(all).map(\.id), ["2"])
        XCTAssertEqual(StatusFilter.shot.apply(all).map(\.id), ["3"])
        XCTAssertEqual(StatusFilter.published.apply(all).map(\.id), ["4"])
    }

    func testScore() {
        let f = Forecast(id: "f", confidence: "", lo: [1, 2, 3, 4], mid: [1000, 5000, 9000, 12_400], hi: [5, 6, 7, 8])
        let script = s("1", type: "Рилс", forecast: f)
        XCTAssertEqual(ScriptScore.views(script), 12_400)
        XCTAssertEqual(ScriptScore.short(12_400), "≈ 12,4 тыс.")
        XCTAssertEqual(ScriptScore.short(1_200_000), "≈ 1,2 млн")
        XCTAssertEqual(ScriptScore.short(850), "≈ 850")
        XCTAssertEqual(ScriptScore.short(20_000), "≈ 20 тыс.")
        XCTAssertEqual(ScriptScore.virality(script), "Низкая")
        var withConf = f; withConf.confidence = "Высокая"
        XCTAssertEqual(ScriptScore.virality(s("2", type: "Рилс", forecast: withConf)), "Высокая")
        XCTAssertNil(ScriptScore.views(s("3", type: "Рилс")))
        XCTAssertNil(ScriptScore.virality(s("3", type: "Рилс")))
    }

    func testProvocativeVariant() {
        let a = ScriptVariant(id: "a", kind: "Вариант Mathias", title: "", body: ScriptBody())
        let b = ScriptVariant(id: "b", kind: "Провокация", title: "", body: ScriptBody())
        let script = s("1", type: "Рилс", variants: [a, b])
        XCTAssertEqual(ScriptScore.provocative(script)?.id, "b")
        XCTAssertEqual(VariantChoice.list(for: script).map(\.id), ["main", "b", "a"])
        XCTAssertNil(ScriptScore.provocative(s("2", type: "Рилс", variants: [a])))
    }
}

/// Статусы, запись в Notion и инфоповоды.
final class StatusAndNewsTests: XCTestCase {
    func testStatusOptionsPerFolder() {
        XCTAssertEqual(StatusFlow.options(for: .carousels), ["Идея", "В работе", "Опубликовано"])
        XCTAssertTrue(StatusFlow.options(for: .reels).contains("Снято"))
        let car = Script(id: "1", title: "c", type: "Карусель", status: "", studioId: "", body: ScriptBody())
        let reel = Script(id: "2", title: "r", type: "Рилс", status: "", studioId: "", body: ScriptBody())
        XCTAssertFalse(StatusFlow.usesPrompter(car))
        XCTAssertTrue(StatusFlow.usesPrompter(reel))
    }

    func testSelectBody() throws {
        let body = NotionWrite.selectBody(property: "Статус", value: "Снято")
        let props = try XCTUnwrap(body["properties"] as? [String: Any])
        let st = try XCTUnwrap(props["Статус"] as? [String: Any])
        XCTAssertEqual((st["select"] as? [String: Any])?["name"] as? String, "Снято")
    }

    func testNewsParseAndSort() throws {
        func rich(_ s: String) -> [[String: Any]] { [["plain_text": s]] }
        let page: [String: Any] = ["id": "n1", "properties": [
            "Название": ["type": "title", "title": rich("Новый Mindestlohn")],
            "Суть": ["type": "rich_text", "rich_text": rich("С января больше")],
            "Источник": ["type": "url", "url": "https://example.org"],
            "Срочность": ["type": "select", "select": ["name": "Горит"]],
            "Потенциал": ["type": "number", "number": 8],
            "Статус": ["type": "select", "select": ["name": "Новый"]],
        ] as [String: Any]]
        let n = try XCTUnwrap(NewsParser.item(page: page))
        XCTAssertEqual(n.title, "Новый Mindestlohn")
        XCTAssertEqual(n.source, "https://example.org")
        XCTAssertEqual(n.potential, 8)
        let a = NewsItem(id: "a", title: "a", urgency: "Не срочно", potential: 10)
        let b = NewsItem(id: "b", title: "b", urgency: "Горит", potential: 5)
        let c = NewsItem(id: "c", title: "c", urgency: "Горит", potential: 9)
        XCTAssertEqual(NewsParser.sorted([a, b, c]).map(\.id), ["c", "b", "a"])
        XCTAssertEqual(NewsFilter.fresh.apply([n, a]).map(\.id), ["n1", "a"])
    }
}

/// Порядок статусов и вид карточки.
final class OrderAndLookTests: XCTestCase {
    func testStatusOrder() {
        func s(_ id: String, _ st: String) -> Script {
            Script(id: id, title: id, type: "Рилс", status: st, studioId: "", body: ScriptBody())
        }
        let list = [s("p", "Опубликовано"), s("i", "Идея"), s("r", "Готов к съёмке"), s("s", "Снято"), s("w", "В работе")]
        XCTAssertEqual(ScriptFolder.reels.items(list).map(\.id), ["s", "r", "w", "i", "p"])
    }

    func testCardOpacity() {
        XCTAssertEqual(CardLook.clampOpacity(0), CardLook.minOpacity)
        XCTAssertEqual(CardLook.clampOpacity(2), 1)
        XCTAssertEqual(CardLook.percent(0.85), "85 %")
    }
}
