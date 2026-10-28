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
