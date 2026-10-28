import XCTest
@testable import CreatorStudio

/// Вопросы аудитории и факт рядом с прогнозом.
final class QuestionsAndFactsTests: XCTestCase {
    private func rich(_ s: String) -> [[String: Any]] { [["plain_text": s]] }

    func testQuestionParseSortFilter() throws {
        let page: [String: Any] = ["id": "q1", "properties": [
            "Вопрос": ["type": "title", "title": rich("Лизинг это деньги в унитаз?")],
            "Тема": ["type": "select", "select": ["name": "Машины"]],
            "Лайки": ["type": "number", "number": 57],
            "Рилс": ["type": "url", "url": "https://www.instagram.com/reel/x/"],
            "Статус": ["type": "select", "select": ["name": "Новый"]],
        ] as [String: Any]]
        let q = try XCTUnwrap(QuestionParser.item(page: page))
        XCTAssertEqual(q.topic, "Машины")
        XCTAssertEqual(q.likes, 57)
        let a = AudienceQuestion(id: "a", title: "a", topic: "Язык", likes: 3, status: "Новый")
        let b = AudienceQuestion(id: "b", title: "b", topic: "Машины", likes: 100, status: "Взял")
        XCTAssertEqual(QuestionParser.sorted([b, a, q]).map(\.id), ["q1", "a", "b"])
        XCTAssertEqual(QuestionParser.topics([a, b, q]), ["Все", "Машины", "Язык"])
        XCTAssertEqual(QuestionParser.filter([a, b, q], topic: "Машины", showAll: false).map(\.id), ["q1"])
        XCTAssertEqual(QuestionParser.filter([a, b, q], topic: "Все", showAll: true).count, 3)
        let props = QuestionParser.scriptProperties(for: q)
        XCTAssertNotNil(props["Название"])
        XCTAssertEqual((props["Статус"] as? [String: Any]).flatMap { $0["select"] as? [String: Any] }?["name"] as? String, "Идея")
    }

    func testPercentAndStats() {
        XCTAssertEqual(ForecastMath.percent("~23%"), 23)
        XCTAssertEqual(ForecastMath.percent("2,0%"), 2)
        XCTAssertNil(ForecastMath.percent("~60–200"))
        XCTAssertEqual(ForecastMath.pct(29.3), "29 %")
        XCTAssertEqual(ForecastMath.pct(0.62), "0,6 %")
        let st = FactStats(hours: 17, views: 9000, skip: 29, avgWatch: 6.5, length: 13, saves: 36, shares: 27)
        XCTAssertEqual(st.retention ?? 0, 50, accuracy: 0.01)
        XCTAssertEqual(st.rate(st.shares) ?? 0, 0.3, accuracy: 0.001)
    }

    func testFactPropsAndNow() throws {
        let page: [String: Any] = ["id": "f1", "properties": [
            "Сценарий": ["type": "relation", "relation": [["id": "s1"]]],
            "Прогноз 24ч": ["type": "number", "number": 7000], "Прогноз 48ч": ["type": "number", "number": 11000],
            "Прогноз 72ч": ["type": "number", "number": 13000], "Прогноз 96ч": ["type": "number", "number": 14000],
            "Факт просмотры": ["type": "number", "number": 9111], "Факт часов": ["type": "number", "number": 17],
            "Факт пропуски": ["type": "number", "number": 29.1],
        ] as [String: Any]]
        let f = try XCTUnwrap(ForecastParser.forecast(page: page, blocks: [])).forecast
        XCTAssertEqual(f.stats?.skip, 29.1)
        XCTAssertEqual(f.actual.first?.hours, 17)
        let now = try XCTUnwrap(ForecastMath.now(f, facts: f.actual))
        XCTAssertEqual(now.expected, 7000 * 17 / 24, accuracy: 1)
    }
}
