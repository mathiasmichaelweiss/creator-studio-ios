import SwiftUI

/// Настройки суфлёра и текст сценария. Хранятся на устройстве.
final class PrompterSettings: ObservableObject {
    @AppStorage("script") var script: String = PrompterSettings.sample
    /// Скорость прокрутки в пунктах в секунду.
    @AppStorage("speed") var speed: Double = 40
    @AppStorage("fontSize") var fontSize: Double = 30
    @AppStorage("showSafeZone") var showSafeZone: Bool = true
    @AppStorage("countdown") var countdown: Int = 3
    /// Режим чтения: суфлёр (текст едет) или карточки (абзац за абзацем, листаешь сам).
    @AppStorage("mode") var mode: ReadingMode = .prompter

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
