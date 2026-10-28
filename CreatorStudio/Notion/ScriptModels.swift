import Foundation

/// Где лежат сценарии в Notion. Это не секреты: без ключа по ним ничего не прочитать.
enum NotionConfig {
    static let scriptsDataSource = "56f3ff11-3a1a-4b98-a99c-83c552bde99b"
    static let variantsDataSource = "886d2a7b-f046-481c-ac54-cfc4a3c35589"
    static let forecastsDataSource = "2b2d559e-2fa4-4bce-8db3-0d4e21a5cfa8"
    static let newsDataSource = "7d9969cd-a0e1-47d0-90f8-0d08b2050ffe"
    static let questionsDataSource = "b311c009-5899-4398-9d8b-52f223296946"
    static let apiVersion = "2025-09-03"
    static let baseURL = URL(string: "https://api.notion.com/v1/")!
}

/// Кусок текста под своим подзаголовком («Подогрев», «Разворот»…). В карточках это одна карточка.
struct ScriptSection: Codable, Equatable, Hashable {
    var label: String?
    var text: String
}

/// Текст сценария или вариации: хук, части, призыв.
struct ScriptBody: Codable, Equatable, Hashable {
    var hook: String = ""
    var sections: [ScriptSection] = []
    var cta: String = ""

    var isEmpty: Bool {
        hook.trimmed.isEmpty && cta.trimmed.isEmpty && sections.allSatisfy { $0.text.trimmed.isEmpty }
    }

    /// Текст для суфлёра: абзацы через пустую строку, чтобы «Карточки» резали ровно по частям.
    var prompterText: String {
        ([hook] + sections.map(\.text) + [cta])
            .map(\.trimmed)
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }
}

struct ScriptVariant: Codable, Equatable, Hashable, Identifiable {
    var id: String
    /// «Провокация», «Вариант Mathias»…
    var kind: String
    var title: String
    var body: ScriptBody
}

struct Script: Codable, Equatable, Hashable, Identifiable {
    var id: String
    var title: String
    var type: String
    var status: String
    var studioId: String
    var body: ScriptBody
    var variantIds: [String] = []
    var variants: [ScriptVariant] = []
    /// Дата и время из Notion («Дата», «Время»). Необязательные: старый кэш без них тоже читается.
    var notionDate: String? = nil
    var notionTime: String? = nil
    var forecast: Forecast? = nil

    /// Вариация берёт хук и призыв основного текста, если своих нет.
    func body(for variant: ScriptVariant?) -> ScriptBody {
        guard let v = variant else { return body }
        var b = v.body
        if b.hook.trimmed.isEmpty { b.hook = body.hook }
        if b.cta.trimmed.isEmpty { b.cta = body.cta }
        if b.sections.isEmpty { b.sections = body.sections }
        return b
    }
}

enum ScriptStatus {
    static let all = ["Снято", "Готов к съёмке", "В работе", "Идея", "Опубликовано"]
    /// Порядок в списке: сначала снятое (его монтировать и публиковать), потом то, что можно снимать,
    /// дальше идеи, опубликованное в самом конце.
    static func rank(_ s: String) -> Int { all.firstIndex(of: s) ?? all.count }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
