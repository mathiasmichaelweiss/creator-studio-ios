import XCTest
@testable import CreatorStudio

/// Разбор ответов Notion, склейка текста и копия на телефоне. Ответы как у настоящего API.
final class NotionParserTests: XCTestCase {
    typealias JSON = [String: Any]

    private func rich(_ s: String) -> [JSON] { [["type": "text", "plain_text": s]] }
    private func block(_ type: String, _ text: String) -> JSON { ["type": type, type: ["rich_text": rich(text)]] }

    private var scriptPage: JSON {
        ["object": "page", "id": "40690246-378a-81a2-8f48-f8831e243ba7", "properties": [
            "Название": ["type": "title", "title": rich("Почему я должен жить как нищий")],
            "Тип": ["type": "select", "select": ["name": "Рилс"]],
            "Статус": ["type": "select", "select": ["name": "Опубликовано"]],
            "ID студии": ["type": "rich_text", "rich_text": rich("reel-nishiy")],
            "Хук": ["type": "rich_text", "rich_text": [["plain_text": "Почему "], ["plain_text": "я должен"]]],
            "CTA": ["type": "rich_text", "rich_text": []],
            "Вариации": ["type": "relation", "relation": [["id": "v1"]]],
        ] as JSON]
    }

    func testScriptProperties() throws {
        let s = try XCTUnwrap(NotionParser.script(page: scriptPage))
        XCTAssertEqual(s.title, "Почему я должен жить как нищий")
        XCTAssertEqual(s.type, "Рилс")
        XCTAssertEqual(s.status, "Опубликовано")
        XCTAssertEqual(s.studioId, "reel-nishiy")
        XCTAssertEqual(s.body.hook, "Почему я должен", "куски rich_text склеиваются")
        XCTAssertEqual(s.body.cta, "")
        XCTAssertEqual(s.variantIds, ["v1"])
    }

    func testPageWithoutTitleIsSkipped() {
        XCTAssertNil(NotionParser.script(page: ["id": "x", "properties": ["Название": ["type": "title", "title": []]]]))
    }

    func testStatusPropertyTypeAlsoWorks() {
        XCTAssertEqual(NotionParser.plainText(["type": "status", "status": ["name": "Идея"]]), "Идея")
        XCTAssertEqual(NotionParser.plainText(["type": "select", "select": NSNull()]), "")
        XCTAssertEqual(NotionParser.plainText(nil), "")
    }

    func testVariantNeedsScriptRelation() throws {
        let page: JSON = ["id": "v1", "properties": [
            "Название": ["type": "title", "title": rich("Провокация")],
            "Вид": ["type": "select", "select": ["name": "Провокация"]],
            "Сценарий": ["type": "relation", "relation": [["id": "s1"]]],
            "Хук": ["type": "rich_text", "rich_text": rich("Острый хук")],
        ] as JSON]
        let parsed = try XCTUnwrap(NotionParser.variant(page: page))
        XCTAssertEqual(parsed.scriptId, "s1")
        XCTAssertEqual(parsed.variant.kind, "Провокация")
        XCTAssertEqual(parsed.variant.body.hook, "Острый хук")

        var orphan = page
        orphan["properties"] = ["Название": ["type": "title", "title": rich("x")]]
        XCTAssertNil(NotionParser.variant(page: orphan))
    }

    func testSectionsFromTextHeadingOnly() {
        let blocks: [JSON] = [
            block("heading_2", "Текст"),
            block("heading_3", "Подогрев"),
            block("paragraph", "Первый абзац."),
            block("paragraph", "Второй абзац."),
            block("heading_3", "Вывод"),
            block("paragraph", "Итог."),
            block("heading_2", "Заметки"),
            block("paragraph", "Это не читать."),
        ]
        XCTAssertEqual(NotionParser.sections(blocks: blocks), [
            ScriptSection(label: "Подогрев", text: "Первый абзац.\nВторой абзац."),
            ScriptSection(label: "Вывод", text: "Итог."),
        ])
    }

    func testOnlyNotesGivesNoSections() {
        let blocks: [JSON] = [block("heading_2", "Заметки"), block("paragraph", "Оценка идеи")]
        XCTAssertEqual(NotionParser.sections(blocks: blocks), [])
    }

    func testPageWithoutHeadingsIsAllText() {
        let blocks: [JSON] = [block("paragraph", "Раз"), block("paragraph", ""), block("paragraph", "Два")]
        XCTAssertEqual(NotionParser.sections(blocks: blocks), [
            ScriptSection(label: nil, text: "Раз"), ScriptSection(label: nil, text: "Два"),
        ])
    }

    func testEmptyLabeledSectionIsDropped() {
        let blocks: [JSON] = [block("heading_2", "Текст"), block("heading_3", "Пусто"), block("heading_3", "Есть"),
                              block("paragraph", "текст"), ["type": "code", "code": ["rich_text": rich("{}")]]]
        XCTAssertEqual(NotionParser.sections(blocks: blocks), [ScriptSection(label: "Есть", text: "текст")])
    }

    func testListPagination() throws {
        let data = try JSONSerialization.data(withJSONObject: ["object": "list", "results": [["id": "a"]],
                                                               "has_more": true, "next_cursor": "c2"])
        let page = try NotionParser.list(data)
        XCTAssertEqual(page.results.count, 1)
        XCTAssertEqual(page.nextCursor, "c2")

        let last = try JSONSerialization.data(withJSONObject: ["object": "list", "results": [],
                                                               "has_more": false, "next_cursor": NSNull()])
        XCTAssertNil(try NotionParser.list(last).nextCursor)
    }

    func testApiErrorMapsToFriendlyText() throws {
        let data = try JSONSerialization.data(withJSONObject: ["object": "error", "status": 404,
                                                               "code": "object_not_found", "message": "x"])
        XCTAssertThrowsError(try NotionParser.list(data)) { err in
            XCTAssertEqual(err as? NotionError, .api(code: "object_not_found", message: "x"))
            XCTAssertTrue((err as? NotionError)?.errorDescription?.contains("Connections") == true)
        }
        XCTAssertTrue(NotionError.api(code: "unauthorized", message: "").errorDescription!.contains("Ключ"))
    }
}

final class ScriptComposeTests: XCTestCase {
    private let main = ScriptBody(hook: "Хук", sections: [
        ScriptSection(label: "Подогрев", text: "Часть 1"),
        ScriptSection(label: nil, text: "  "),
        ScriptSection(label: "Вывод", text: "Часть 2\nстрока"),
    ], cta: "Подпишись")

    func testPrompterTextIsParagraphsForCards() {
        XCTAssertEqual(main.prompterText, "Хук\n\nЧасть 1\n\nЧасть 2\nстрока\n\nПодпишись")
        XCTAssertEqual(Paragraphs.split(main.prompterText).count, 4, "карточка на хук, части и призыв")
    }

    func testVariantFallsBackToMainHookAndCta() {
        let script = Script(id: "s", title: "T", type: "Рилс", status: "Идея", studioId: "", body: main)
        let v = ScriptVariant(id: "v", kind: "Провокация", title: "",
                              body: ScriptBody(hook: "", sections: [ScriptSection(label: nil, text: "Остро")], cta: ""))
        let b = script.body(for: v)
        XCTAssertEqual(b.hook, "Хук")
        XCTAssertEqual(b.cta, "Подпишись")
        XCTAssertEqual(b.sections.map(\.text), ["Остро"])
        XCTAssertEqual(script.body(for: nil), main)
    }

    func testEmptyBody() {
        XCTAssertTrue(ScriptBody().isEmpty)
        XCTAssertTrue(ScriptBody(hook: " ", sections: [ScriptSection(label: "x", text: "")], cta: "").isEmpty)
        XCTAssertFalse(main.isEmpty)
    }

    func testVariantChoiceListsMainFirst() {
        var script = Script(id: "s", title: "T", type: "", status: "", studioId: "", body: main)
        XCTAssertEqual(VariantChoice.list(for: script).map(\.title), ["Основной"])
        script.variants = [ScriptVariant(id: "v", kind: "Провокация", title: "", body: ScriptBody())]
        XCTAssertEqual(VariantChoice.list(for: script).map(\.title), ["Основной", "Провокация"])
    }
}

@MainActor
final class ScriptStoreTests: XCTestCase {
    private func script(_ id: String, _ title: String, _ status: String) -> Script {
        Script(id: id, title: title, type: "Рилс", status: status, studioId: "", body: ScriptBody(hook: title))
    }

    func testMergeAttachesVariantsIgnoringDashes() {
        let v = ScriptVariant(id: "v", kind: "Провокация", title: "", body: ScriptBody())
        let merged = ScriptStore.merge(scripts: [script("40690246-378a-81a2", "A", "Снято")],
                                       variants: [("40690246378a81A2", v), ("missing", v)])
        XCTAssertEqual(merged[0].variants, [v])
    }

    func testMergeSortsReadyFirstThenByTitle() {
        let merged = ScriptStore.merge(scripts: [
            script("1", "Б", "Идея"), script("2", "Я", "Готов к съёмке"),
            script("3", "А", "Идея"), script("4", "В", "Странный"), script("5", "Г", "Опубликовано"),
        ], variants: [])
        XCTAssertEqual(merged.map(\.title), ["Я", "А", "Б", "Г", "В"])
    }

    func testStatusFilter() {
        let all = [script("1", "a", "Готов к съёмке"), script("2", "b", "Идея"), script("3", "c", "Снято")]
        XCTAssertEqual(StatusFilter.ready.apply(all).map(\.id), ["1"])
        XCTAssertEqual(StatusFilter.idea.apply(all).map(\.id), ["2"])
        XCTAssertEqual(StatusFilter.all.apply(all).count, 3)
    }

    func testCacheRoundTripAndStoreLoadsIt() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("scripts-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let cache = ScriptCache(url: url)
        XCTAssertNil(cache.load())

        var s = script("1", "Кэш", "Идея")
        s.body.sections = [ScriptSection(label: "Часть", text: "Текст")]
        s.variants = [ScriptVariant(id: "v", kind: "Провокация", title: "П", body: ScriptBody(hook: "h"))]
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        cache.save(CachedScripts(date: date, scripts: [s]))

        XCTAssertEqual(cache.load(), CachedScripts(date: date, scripts: [s]))
        let store = ScriptStore(cache: cache)
        XCTAssertEqual(store.scripts, [s])
        XCTAssertEqual(store.lastSync, date)
    }
}
