import SwiftUI

/// Настройки суфлёра и текст сценария. Хранятся на устройстве.
final class PrompterSettings: ObservableObject {
    @AppStorage("script") var script: String = PrompterSettings.sample
    /// Название выбранного сценария из Notion (пусто, если текст свой).
    @AppStorage("scriptTitle") var scriptTitle: String = ""
    /// Скорость прокрутки в пунктах в секунду.
    @AppStorage("speed") var speed: Double = 40
    @AppStorage("fontSize") var fontSize: Double = 30
    @AppStorage("showSafeZone") var showSafeZone: Bool = true
    @AppStorage("countdown") var countdown: Int = 3
    /// Режим чтения: суфлёр (текст едет) или карточки (абзац за абзацем, листаешь сам).
    @AppStorage("mode") var mode: ReadingMode = .prompter
    /// Как едет суфлёр: с постоянной скоростью или за голосом.
    @AppStorage("scrollMode") var scrollMode: ScrollMode = .speed
    /// Тема и размер текста, как переключатели на razberemsya.de.
    @AppStorage("theme") var theme: AppTheme = .system
    @AppStorage("textScale") var textScale: TextScale = .normal
    /// Подложка карточек: цвет и прозрачность (шестерёнка на карточке).
    @AppStorage("cardTone") var cardTone: CardTone = .dark
    @AppStorage("cardOpacity") var cardOpacity: Double = 0.85
    /// Карточка целиком, без деления на абзацы (инфоповод на экране при записи).
    @AppStorage("wholeCard") var wholeCard: Bool = false

    /// Итоговый размер текста суфлёра и карточек с учётом «Обычный / Крупный».
    var prompterFontSize: Double { fontSize * textScale.prompterFactor }

    static let sample = """
    Вставь сюда текст сценария.

    Суфлёр крутится, пока идёт запись. Пауза одной кнопкой останавливает и запись, и текст. \
    Play продолжает в тот же файл после отсчёта.
    """
}

enum ReadingMode: String, CaseIterable, Identifiable {
    case prompter, cards
    var id: String { rawValue }
    var title: String { self == .prompter ? "Суфлёр" : "Карточки" }
}

enum ScrollMode: String, CaseIterable, Identifiable {
    case speed, voice
    var id: String { rawValue }
    var title: String { self == .speed ? "По скорости" : "По голосу" }
}
