import Foundation

/// Разбор ответов Notion API в модели приложения. Чистые функции, без сети: так их легко тестировать.
enum NotionParser {
    typealias JSON = [String: Any]

    // MARK: Свойства страницы

    static func plainText(_ property: Any?) -> String {
        guard let p = property as? JSON, let type = p["type"] as? String else { return "" }
        switch type {
        case "title", "rich_text":
            return richText(p[type])
        case "select", "status":
            return (p[type] as? JSON)?["name"] as? String ?? ""
        default:
            return ""
        }
    }

    static func dateStart(_ property: Any?) -> String? {
        guard let p = property as? JSON, let d = p["date"] as? JSON, let start = d["start"] as? String,
              !start.isEmpty else { return nil }
        return start
    }

    static func number(_ property: Any?) -> Double? {
        guard let p = property as? JSON else { return nil }
        if let n = p["number"] as? Double { return n }
        if let n = p["number"] as? Int { return Double(n) }
        return nil
    }

    static func relationIds(_ property: Any?) -> [String] {
        guard let p = property as? JSON, let rel = p["relation"] as? [JSON] else { return [] }
        return rel.compactMap { $0["id"] as? String }
    }

    static func richText(_ value: Any?) -> String {
        guard let parts = value as? [JSON] else { return "" }
        return parts.compactMap { $0["plain_text"] as? String }.joined()
    }

    /// Строка базы «Сценарии» без текста страницы (текст приходит отдельно, блоками).
    static func script(page: JSON) -> Script? {
        guard let id = page["id"] as? String, let props = page["properties"] as? JSON else { return nil }
        let title = plainText(props["Название"])
        guard !title.isEmpty else { return nil }
        return Script(
            id: id,
            title: title,
            type: plainText(props["Тип"]),
            status: plainText(props["Статус"]),
            studioId: plainText(props["ID студии"]),
            body: ScriptBody(hook: plainText(props["Хук"]), sections: fieldSections(plainText(props["Текст"])), cta: plainText(props["CTA"])),
            variantIds: relationIds(props["Вариации"]),
            notionDate: dateStart(props["Дата"]),
            notionTime: plainText(props["Время"]).isEmpty ? nil : plainText(props["Время"])
        )
    }

    /// Строка базы «Вариации». Возвращает id основного сценария и саму вариацию.
    static func variant(page: JSON) -> (scriptId: String, variant: ScriptVariant)? {
        guard let id = page["id"] as? String, let props = page["properties"] as? JSON else { return nil }
        guard let scriptId = relationIds(props["Сценарий"]).first else { return nil }
        let v = ScriptVariant(
            id: id,
            kind: plainText(props["Вид"]).isEmpty ? "Вариант" : plainText(props["Вид"]),
            title: plainText(props["Название"]),
            body: ScriptBody(hook: plainText(props["Хук"]), sections: [], cta: plainText(props["CTA"]))
        )
        return (scriptId, v)
    }

    /// Поле «Текст» базы: абзацы через пустую строку становятся частями.
    /// Нужно, когда текст записан в поле, а не в тело страницы.
    static func fieldSections(_ text: String) -> [ScriptSection] {
        text.replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { ScriptSection(label: nil, text: $0) }
    }

    // MARK: Текст страницы

    /// Берёт из блоков страницы раздел «## Текст»: каждый «### Подзаголовок» начинает новую часть,
    /// абзацы под ним складываются в её текст. «## Заметки» и прочее пропускается.
    /// Если раздела «Текст» нет, а заголовков второго уровня тоже нет, текстом считается вся страница.
    static func sections(blocks: [JSON]) -> [ScriptSection] {
        let hasH2 = blocks.contains { ($0["type"] as? String) == "heading_2" }
        var inText = !hasH2
        var result: [ScriptSection] = []

        for block in blocks {
            guard let type = block["type"] as? String else { continue }
            let text = richText((block[type] as? JSON)?["rich_text"]).trimmed
            switch type {
            case "heading_1", "heading_2":
                inText = text.lowercased() == "текст"
            case "heading_3":
                guard inText else { continue }
                result.append(ScriptSection(label: text.isEmpty ? nil : text, text: ""))
            case "paragraph", "bulleted_list_item", "numbered_list_item", "quote", "callout":
                guard inText, !text.isEmpty else { continue }
                if let last = result.indices.last, result[last].label != nil || result[last].text.isEmpty {
                    result[last].text = result[last].text.isEmpty ? text : result[last].text + "\n" + text
                } else {
                    result.append(ScriptSection(label: nil, text: text))
                }
            default:
                continue
            }
        }
        return result.filter { !$0.text.trimmed.isEmpty }
    }

    /// Ответ списка: страницы, есть ли продолжение, курсор.
    static func list(_ data: Data) throws -> (results: [JSON], nextCursor: String?) {
        guard let obj = try JSONSerialization.jsonObject(with: data) as? JSON else {
            throw NotionError.badResponse
        }
        if (obj["object"] as? String) == "error" {
            throw NotionError.api(code: obj["code"] as? String ?? "", message: obj["message"] as? String ?? "")
        }
        let results = obj["results"] as? [JSON] ?? []
        let more = obj["has_more"] as? Bool ?? false
        return (results, more ? obj["next_cursor"] as? String : nil)
    }
}

enum NotionError: LocalizedError, Equatable {
    case noKey
    case badResponse
    case http(Int)
    case api(code: String, message: String)

    var errorDescription: String? {
        switch self {
        case .noKey:
            return "Нет ключа Notion. Добавь его в настройках."
        case .badResponse:
            return "Notion ответил непонятно. Попробуй ещё раз."
        case .http(let code):
            return "Notion недоступен (код \(code)). Показываю сохранённые сценарии."
        case .api(let code, _):
            switch code {
            case "unauthorized": return "Ключ Notion не подходит. Проверь его в настройках."
            case "object_not_found", "restricted_resource":
                return "У ключа нет доступа к странице «Студия креатора». В Notion: ••• → Connections → Студия."
            case "rate_limited": return "Notion просит подождать. Попробуй через минуту."
            default: return "Ошибка Notion: \(code)."
            }
        }
    }
}
