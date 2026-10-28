import Foundation

/// Папки студии по полю «Тип» в Notion. Чистая логика, без UI: её проверяют тесты.
enum ScriptFolder: String, CaseIterable, Identifiable, Hashable {
    case reels, carousels, formats, other
    var id: String { rawValue }

    var title: String {
        switch self {
        case .reels: return "Рилсы"
        case .carousels: return "Карусели"
        case .formats: return "Форматы"
        case .other: return "Остальное"
        }
    }

    var icon: String {
        switch self {
        case .reels: return "video.fill"
        case .carousels: return "square.stack.fill"
        case .formats: return "rectangle.3.group.fill"
        case .other: return "tray.fill"
        }
    }

    /// Тип из Notion → папка. Сторис и интеграции пока лежат в «Остальном».
    static func of(type: String) -> ScriptFolder {
        switch type.trimmed.lowercased() {
        case "рилс", "рилсы", "reels", "reel": return .reels
        case "карусель", "карусели", "carousel": return .carousels
        case "формат", "форматы", "рубрика": return .formats
        default: return .other
        }
    }

    func items(_ scripts: [Script]) -> [Script] {
        scripts.filter { ScriptFolder.of(type: $0.type) == self }
    }

    /// Папки для экрана: три основные всегда, «Остальное» только если там что-то есть.
    static func visible(_ scripts: [Script]) -> [ScriptFolder] {
        let main: [ScriptFolder] = [.reels, .carousels, .formats]
        return other.items(scripts).isEmpty ? main : main + [.other]
    }
}

/// Фильтр по статусу внутри папки.
enum StatusFilter: String, CaseIterable, Identifiable {
    case all, idea, inWork, ready, shot, published
    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "Все"
        case .idea: return "Идея"
        case .inWork: return "В работе"
        case .ready: return "К съёмке"
        case .shot: return "Снято"
        case .published: return "Опубликовано"
        }
    }

    /// Название статуса в Notion. У «Все» его нет.
    var notionName: String? {
        switch self {
        case .all: return nil
        case .idea: return "Идея"
        case .inWork: return "В работе"
        case .ready: return "Готов к съёмке"
        case .shot: return "Снято"
        case .published: return "Опубликовано"
        }
    }

    func apply(_ s: [Script]) -> [Script] {
        guard let name = notionName else { return s }
        return s.filter { $0.status.trimmed == name }
    }

    func count(_ s: [Script]) -> Int { apply(s).count }
}

/// Оценка сценария из «Прогнозов» и провокационная версия из «Вариаций».
enum ScriptScore {
    /// Ожидаемые просмотры за 96 часов (средняя линия прогноза).
    static func views(_ s: Script) -> Double? {
        guard let f = s.forecast, f.isUsable else { return nil }
        return f.mid.last
    }

    /// Коротко для чипа: «≈ 12 тыс.», «≈ 1,2 млн».
    static func short(_ v: Double) -> String {
        func fmt(_ x: Double) -> String {
            let r = (x * 10).rounded() / 10
            let s = r == r.rounded() ? String(Int(r)) : String(r)
            return s.replacingOccurrences(of: ".", with: ",")
        }
        if v >= 1_000_000 { return "≈ \(fmt(v / 1_000_000)) млн" }
        if v >= 1_000 { return "≈ \(fmt(v / 1_000)) тыс." }
        return "≈ \(Int(v.rounded()))"
    }

    /// Вирусность из уверенности прогноза или по просмотрам, если уверенность не указана.
    static func virality(_ s: Script) -> String? {
        if let c = s.forecast?.confidence.trimmed, !c.isEmpty { return c }
        guard let v = views(s) else { return nil }
        if v >= 100_000 { return "Высокая" }
        if v >= 20_000 { return "Средняя" }
        return "Низкая"
    }

    static func isProvocative(_ v: ScriptVariant) -> Bool {
        let k = (v.kind + " " + v.title).lowercased()
        return k.contains("провока") || k.contains("остр")
    }

    static func provocative(_ s: Script) -> ScriptVariant? {
        s.variants.first(where: isProvocative)
    }
}

/// Какие статусы можно выбрать в папке. У каруселей нет съёмки.
enum StatusFlow {
    static func options(for folder: ScriptFolder) -> [String] {
        switch folder {
        case .carousels: return ["Идея", "В работе", "Опубликовано"]
        default: return ["Идея", "В работе", "Готов к съёмке", "Снято", "Опубликовано"]
        }
    }

    /// Карусель не читают в суфлёре, её текст копируют.
    static func usesPrompter(_ s: Script) -> Bool { ScriptFolder.of(type: s.type) != .carousels }
}

/// Запись в Notion: тело запроса и понятные ошибки.
enum NotionWrite {
    static func selectBody(property: String, value: String) -> [String: Any] {
        ["properties": [property: ["select": ["name": value]]]]
    }

    static func message(for error: Error) -> String {
        if case NotionError.api(let code, _) = error, code == "restricted_resource" || code == "unauthorized" {
            return "Notion не дал изменить. В Notion: Settings → Connections → Студия, включи «Update content»."
        }
        return (error as? LocalizedError)?.errorDescription ?? "Не получилось сохранить в Notion. Попробуй ещё раз."
    }
}
