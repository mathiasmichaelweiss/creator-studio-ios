import EventKit
import XCTest
@testable import CreatorStudio

/// Этап 3: прогнозы из Notion, расчёты графика, план и календарь.
final class ForecastParserTests: XCTestCase {
    typealias JSON = [String: Any]

    private func rich(_ s: String) -> [JSON] { [["plain_text": s]] }
    private func block(_ type: String, _ text: String) -> JSON { ["type": type, type: ["rich_text": rich(text)]] }

    private func page(_ extra: JSON = [:]) -> JSON {
        var props: JSON = [
            "Название": ["type": "title", "title": rich("Прогноз: нищий")],
            "Сценарий": ["type": "relation", "relation": [["id": "s1"]]],
            "Уверенность": ["type": "rich_text", "rich_text": rich("высокая")],
            "Репосты": ["type": "rich_text", "rich_text": rich("2,0%")],
            "Прогноз 24ч": ["type": "number", "number": 15000],
            "Прогноз 48ч": ["type": "number", "number": 19000],
            "Прогноз 72ч": ["type": "number", "number": 21500],
            "Прогноз 96ч": ["type": "number", "number": 23000],
            "Минимум 96ч": ["type": "number", "number": 17000],
            "Максимум 96ч": ["type": "number", "number": 38000],
        ]
        extra.forEach { props[$0.key] = $0.value }
        return ["id": "f1", "properties": props]
    }

    func testBandAndFactFromCodeBlocks() throws {
        let blocks: [JSON] = [
            block("heading_2", "Прогноз"),
            block("code", #"{"lo": [1, 2, 3, 4], "mid": [10, 20, 30, 40], "hi": [100, 200, 300, 400]}"#),
            block("heading_2", "Факт"),
            block("code", #"[{"h": 52, "v": 20631}, {"h": 1, "v": 532}]"#),
        ]
        let r = try XCTUnwrap(ForecastParser.forecast(page: page(), blocks: blocks))
        XCTAssertEqual(r.scriptId, "s1")
        XCTAssertEqual(r.forecast.lo, [1, 2, 3, 4])
        XCTAssertEqual(r.forecast.mid, [10, 20, 30, 40])
        XCTAssertEqual(r.forecast.hi, [100, 200, 300, 400])
        XCTAssertEqual(r.forecast.actual, [FactPoint(hours: 1, views: 532), FactPoint(hours: 52, views: 20631)])
        XCTAssertEqual(r.forecast.confidence, "высокая")
        XCTAssertEqual(r.forecast.shares, "2,0%")
    }

    func testFallsBackToNumberProperties() throws {
        let r = try XCTUnwrap(ForecastParser.forecast(page: page(), blocks: []))
        XCTAssertEqual(r.forecast.mid, [15000, 19000, 21500, 23000])
        XCTAssertEqual(r.forecast.lo[3], 17000, accuracy: 0.001)
        XCTAssertEqual(r.forecast.hi[3], 38000, accuracy: 0.001)
        XCTAssertEqual(r.forecast.actual, [])
    }

    func testFactViewsPropertyWhenNoFactBlock() throws {
        let p = page(["Факт просмотры": ["type": "number", "number": 20631]])
        XCTAssertEqual(try XCTUnwrap(ForecastParser.forecast(page: p, blocks: [])).forecast.actual,
                       [FactPoint(hours: 96, views: 20631)])
    }

    func testBrokenJsonIsIgnored() throws {
        let blocks: [JSON] = [block("heading_2", "Прогноз"), block("code", "{не json"),
                              block("heading_2", "Факт"), block("code", "[]")]
        let r = try XCTUnwrap(ForecastParser.forecast(page: page(), blocks: blocks))
        XCTAssertEqual(r.forecast.mid, [15000, 19000, 21500, 23000], "берутся числа из свойств")
        XCTAssertEqual(r.forecast.actual, [])
    }

    func testNoScriptOrNoNumbersMeansNoForecast() {
        var orphan = page()
        var props = orphan["properties"] as! JSON
        props["Сценарий"] = ["type": "relation", "relation": []]
        orphan["properties"] = props
        XCTAssertNil(ForecastParser.forecast(page: orphan, blocks: []))

        let noNumbers: JSON = ["id": "f", "properties": ["Сценарий": ["type": "relation", "relation": [["id": "s"]]]]]
        XCTAssertNil(ForecastParser.forecast(page: noNumbers, blocks: []))
    }

    func testScriptDateFromNotion() throws {
        let p: JSON = ["id": "s", "properties": [
            "Название": ["type": "title", "title": rich("X")],
            "Дата": ["type": "date", "date": ["start": "2026-10-28", "end": NSNull()]],
            "Время": ["type": "rich_text", "rich_text": rich("17:00")],
        ] as JSON]
        let s = try XCTUnwrap(NotionParser.script(page: p))
        XCTAssertEqual(s.notionDate, "2026-10-28")
        XCTAssertEqual(s.notionTime, "17:00")
        XCTAssertNil(NotionParser.dateStart(["type": "date", "date": NSNull()]))
    }
}

final class ForecastMathTests: XCTestCase {
    private let f = Forecast(id: "f", lo: [10, 20, 30, 40], mid: [100, 200, 300, 400], hi: [1000, 2000, 3000, 4000])

    func testBandStartsAtZero() {
        let b = ForecastMath.band(f)
        XCTAssertEqual(b.map(\.hours), [0, 24, 48, 72, 96])
        XCTAssertEqual(b.first?.mid, 0)
        XCTAssertEqual(b.last?.hi, 4000)
        XCTAssertEqual(ForecastMath.band(Forecast(id: "x")), [])
    }

    func testExpectedInterpolates() {
        XCTAssertEqual(ForecastMath.expected(f, at: 12)!, 50, accuracy: 0.001)
        XCTAssertEqual(ForecastMath.expected(f, at: 36)!, 150, accuracy: 0.001)
        XCTAssertEqual(ForecastMath.expected(f, at: 96)!, 400, accuracy: 0.001)
        XCTAssertEqual(ForecastMath.expected(f, at: 150)!, 400, accuracy: 0.001)
        XCTAssertNil(ForecastMath.expected(Forecast(id: "x"), at: 10))
    }

    func testVerdict() {
        XCTAssertEqual(ForecastMath.verdict(f, facts: []), .noData)
        XCTAssertEqual(ForecastMath.verdict(f, facts: [FactPoint(hours: 24, views: 105)]), .onTrack)
        XCTAssertEqual(ForecastMath.verdict(f, facts: [FactPoint(hours: 24, views: 150)]), .above(percent: 50))
        XCTAssertEqual(ForecastMath.verdict(f, facts: [FactPoint(hours: 1, views: 1), FactPoint(hours: 48, views: 100)]),
                       .below(percent: 50), "сравнивается последняя точка")
        XCTAssertEqual(ForecastMath.Verdict.above(percent: 12).text, "Выше прогноза на 12%")
    }

    func testRealNishiyIsAboveCorridorStart() {
        // «Нищий»: через 52 ч 20 631 при ожидании ~19 400 → по прогнозу (в пределах 10%).
        let nishiy = Forecast(id: "n", lo: [14000, 15500, 16500, 17000], mid: [15000, 19000, 21500, 23000],
                              hi: [18000, 28000, 34000, 38000])
        XCTAssertEqual(ForecastMath.verdict(nishiy, facts: [FactPoint(hours: 52, views: 20631)]), .onTrack)
    }

    func testMergedFactsManualWins() {
        let m = ForecastMath.merged(notion: [FactPoint(hours: 24, views: 1), FactPoint(hours: 1, views: 5)],
                                    manual: [FactPoint(hours: 24, views: 2), FactPoint(hours: 96, views: 9)])
        XCTAssertEqual(m, [FactPoint(hours: 1, views: 5), FactPoint(hours: 24, views: 2), FactPoint(hours: 96, views: 9)])
    }

    func testCompactNumbers() {
        XCTAssertEqual(ForecastMath.compact(950), "950")
        XCTAssertEqual(ForecastMath.compact(1000), "1 тыс.")
        XCTAssertEqual(ForecastMath.compact(20631), "20,6 тыс.")
        XCTAssertEqual(ForecastMath.compact(150000), "150 тыс.")
    }

    func testFactInput() {
        XCTAssertEqual(FactInput.views("20 631"), 20631)
        XCTAssertEqual(FactInput.views("20.631"), 20631)
        XCTAssertNil(FactInput.views(""))
        XCTAssertNil(FactInput.views("0"))
    }
}

@MainActor
final class PlanTests: XCTestCase {
    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return c
    }()

    private func at(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    private func script(_ id: String, status: String = "Готов к съёмке", date: String? = nil, time: String? = nil) -> Script {
        Script(id: id, title: id, type: "Рилс", status: status, studioId: "", body: ScriptBody(hook: "Хук", cta: "CTA"),
               notionDate: date, notionTime: time)
    }

    func testNotionDateParsing() {
        XCTAssertEqual(PlanMath.date(notionDate: "2026-10-28", time: "17:00", calendar: cal), at(2026, 10, 28, 17))
        XCTAssertEqual(PlanMath.date(notionDate: "2026-10-28", time: "8.30", calendar: cal), at(2026, 10, 28, 8, 30))
        XCTAssertEqual(PlanMath.date(notionDate: "2026-10-28", time: nil, calendar: cal), at(2026, 10, 28, 9))
        XCTAssertEqual(PlanMath.date(notionDate: "2026-10-28", time: "вечером", calendar: cal), at(2026, 10, 28, 9))
        XCTAssertEqual(PlanMath.date(notionDate: "2026-10-28T16:00:00.000+00:00", time: nil, calendar: cal),
                       at(2026, 10, 28, 17))
        XCTAssertNil(PlanMath.date(notionDate: nil, time: "17:00"))
        XCTAssertNil(PlanMath.date(notionDate: "завтра", time: nil))
    }

    func testLocalPlanBeatsNotionAndSorts() {
        let scripts = [script("a", date: "2026-10-30", time: "10:00"), script("b"), script("c", date: "2026-10-29")]
        let plans = ["a": PlanEntry(date: at(2026, 10, 28, 12), kind: .publish)]
        let items = PlanMath.items(scripts: scripts, plans: plans)
        XCTAssertEqual(items.map(\.id), ["a", "c"])
        XCTAssertEqual(items[0].kind, .publish)
        XCTAssertEqual(items[1].kind, .shoot)
    }

    func testDefaultKind() {
        XCTAssertEqual(PlanMath.defaultKind(for: script("x", status: "Готов к съёмке")), .shoot)
        XCTAssertEqual(PlanMath.defaultKind(for: script("x", status: "Снято")), .publish)
    }

    func testDaysGroupAndHidePast() {
        let now = at(2026, 10, 28, 12)
        let items = [
            PlanMath.Item(script: script("old"), date: at(2026, 10, 27, 17), kind: .shoot, inCalendar: false),
            PlanMath.Item(script: script("late"), date: at(2026, 10, 28, 20), kind: .shoot, inCalendar: false),
            PlanMath.Item(script: script("early"), date: at(2026, 10, 28, 8), kind: .shoot, inCalendar: false),
            PlanMath.Item(script: script("next"), date: at(2026, 10, 30, 9), kind: .publish, inCalendar: false),
        ]
        let days = PlanMath.days(items, now: now, calendar: cal)
        XCTAssertEqual(days.count, 2)
        XCTAssertEqual(days[0].items.map(\.id), ["early", "late"], "сегодняшние остаются, даже если время прошло")
        XCTAssertEqual(days[1].items.map(\.id), ["next"])
    }

    func testDayTitles() {
        let now = at(2026, 10, 28, 12)
        XCTAssertEqual(PlanSection.dayTitle(at(2026, 10, 28, 20), now: now, calendar: cal), "Сегодня")
        XCTAssertEqual(PlanSection.dayTitle(at(2026, 10, 29, 9), now: now, calendar: cal), "Завтра")
        XCTAssertTrue(PlanSection.dayTitle(at(2026, 10, 31), now: now, calendar: cal).contains("31"))
    }

    func testNextSlotIs17() {
        let before = PlanSchedule.nextSlot(now: at(2026, 10, 28, 10), calendar: cal)
        XCTAssertEqual(before, at(2026, 10, 28, 17))
        let after = PlanSchedule.nextSlot(now: at(2026, 10, 28, 18), calendar: cal)
        XCTAssertEqual(after, at(2026, 10, 29, 17))
    }

    func testPlanStorePersists() {
        let suite = "plan-tests-\(UUID())"
        let d = UserDefaults(suiteName: suite)!
        defer { d.removePersistentDomain(forName: suite) }

        let store = PlanStore(defaults: d)
        store.setPlan(PlanEntry(date: at(2026, 11, 1, 17), kind: .publish), for: "s")
        store.markInCalendar("s")
        store.addFact(FactPoint(hours: 24, views: 100), for: "s")
        store.addFact(FactPoint(hours: 24, views: 150), for: "s")
        store.addFact(FactPoint(hours: 1, views: 10), for: "s")

        let again = PlanStore(defaults: d)
        XCTAssertEqual(again.plans["s"], PlanEntry(date: at(2026, 11, 1, 17), kind: .publish, inCalendar: true))
        XCTAssertEqual(again.manualFacts["s"], [FactPoint(hours: 1, views: 10), FactPoint(hours: 24, views: 150)])

        again.removeFact(hours: 1, for: "s")
        again.setPlan(nil, for: "s")
        let third = PlanStore(defaults: d)
        XCTAssertNil(third.plans["s"])
        XCTAssertEqual(third.manualFacts["s"], [FactPoint(hours: 24, views: 150)])
    }

    func testCalendarEventContent() {
        let item = PlanMath.Item(script: script("Нищий"), date: at(2026, 10, 28, 17), kind: .publish, inCalendar: false)
        let e = CalendarExport.event(for: item, store: EKEventStore())
        XCTAssertEqual(e.title, "Публикация: Нищий")
        XCTAssertEqual(e.startDate, at(2026, 10, 28, 17))
        XCTAssertEqual(e.endDate.timeIntervalSince(e.startDate), 900)
        XCTAssertEqual(e.notes, "Хук\n\nCTA")
        XCTAssertEqual(e.alarms?.first?.relativeOffset, -1800)
    }

    func testOldCacheWithoutNewFieldsStillDecodes() throws {
        let old = #"{"id":"s","title":"T","type":"","status":"","studioId":"","body":{"hook":"","sections":[],"cta":""},"variantIds":[],"variants":[]}"#
        let s = try JSONDecoder().decode(Script.self, from: Data(old.utf8))
        XCTAssertNil(s.forecast)
        XCTAssertNil(s.notionDate)
    }
}
