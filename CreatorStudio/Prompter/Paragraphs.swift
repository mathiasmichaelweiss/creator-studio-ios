import Foundation

/// Делит сценарий на абзацы для режима «Карточки».
enum Paragraphs {
    /// Абзацы разделены пустой строкой. Если пустых строк нет, каждая строка становится абзацем.
    static func split(_ text: String) -> [String] {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        let byBlank = normalized
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if byBlank.count > 1 { return byBlank }
        let byLine = normalized
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return byLine.isEmpty ? [] : (byLine.count > 1 ? byLine : byBlank)
    }

    /// Индекс, зажатый в границы списка.
    static func clamp(_ index: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return min(max(index, 0), count - 1)
    }
}
