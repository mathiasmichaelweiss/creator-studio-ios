import SwiftUI
import UIKit

/// Дизайн-токены экосистемы, один в один с razberemsya.de (CSS-переменные :root и тёмная тема).
enum Palette {
    static let bg = dynamic(light: 0xF7F7F6, dark: 0x121212)
    static let surface = dynamic(light: 0xFFFFFF, dark: 0x1C1C1B)
    static let ink = dynamic(light: 0x111111, dark: 0xF2F2F0)
    static let ink2 = dynamic(light: 0x5C5C5A, dark: 0xB5B5B0)
    static let ink3 = dynamic(light: 0x6B6B68, dark: 0x9C9C97)
    static let line = dynamic(light: 0xE6E6E4, dark: 0x2E2E2C)
    static let chip = dynamic(light: 0xEDEDEB, dark: 0x262625)
    static let soft = dynamic(light: 0xF2F2F0, dark: 0x242423)
    /// Кнопка: чёрная в светлой теме, светлая в тёмной.
    static let btn = dynamic(light: 0x111111, dark: 0xF2F2F0)
    static let btnInk = dynamic(light: 0xFFFFFF, dark: 0x111111)
    static let okBg = dynamic(light: 0xEAF6EE, dark: 0x16301F)
    static let okInk = dynamic(light: 0x1E6B3A, dark: 0x8FD9A8)
    static let mark = dynamic(light: 0xFFF1B8, dark: 0x5A4A10)

    /// Фирменный оранжевый из логотипа и баннера сайта.
    static let brand = Color(hex: 0xFF5A2A)
    static let brandLight = Color(hex: 0xFFD08A)
    static let brandDeep = Color(hex: 0x7A2416)

    /// Градиент логотипа разберемся.de (три радиальных пятна).
    static var brandGradient: some View {
        ZStack {
            brand
            RadialGradient(colors: [brandLight, .clear], center: UnitPoint(x: 0.72, y: 0.28), startRadius: 0, endRadius: 60)
            RadialGradient(colors: [brandDeep.opacity(0.9), .clear], center: UnitPoint(x: 0.22, y: 0.78), startRadius: 0, endRadius: 50)
        }
    }

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light) })
    }
}

/// Скругления сайта: чипы и кнопки 999, карточки 22, крупные блоки 36, поля 16.
enum Radius {
    static let field: CGFloat = 16
    static let card: CGFloat = 22
    static let block: CGFloat = 36
}

/// Шрифт сайта: Inter (вшит в приложение, лицензия OFL).
enum Typo {
    static func inter(_ size: CGFloat, _ weight: Font.Weight = .regular, relativeTo style: Font.TextStyle = .body) -> Font {
        .custom(postScriptName(weight), size: size, relativeTo: style)
    }

    /// Без масштабирования Dynamic Type: для суфлёра, где размер задаёт сам пользователь.
    static func interFixed(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .custom(postScriptName(weight), fixedSize: size)
    }

    static func postScriptName(_ weight: Font.Weight) -> String {
        switch weight {
        case .bold, .heavy, .black: return "Inter-Bold"
        case .semibold: return "Inter-SemiBold"
        case .medium: return "Inter-Medium"
        default: return "Inter-Regular"
        }
    }
}

extension Color {
    init(hex: UInt32) { self.init(UIColor(hex: hex)) }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

// MARK: Настройки внешнего вида (как на сайте)

enum AppTheme: String, CaseIterable, Identifiable {
    case light, dark, system
    var id: String { rawValue }
    var title: String {
        switch self { case .light: "Светлая"; case .dark: "Тёмная"; case .system: "Система" }
    }
    var scheme: ColorScheme? {
        switch self { case .light: .light; case .dark: .dark; case .system: nil }
    }
}

enum TextScale: String, CaseIterable, Identifiable {
    case normal, large
    var id: String { rawValue }
    var title: String { self == .normal ? "Обычный" : "Крупный" }
    var dynamicType: DynamicTypeSize { self == .normal ? .large : .xxLarge }
    /// Множитель для текста суфлёра и карточек.
    var prompterFactor: Double { self == .normal ? 1.0 : 1.2 }
}

// MARK: Компоненты

/// Чёрная (в тёмной теме светлая) кнопка-пилюля, как «Telegram» на сайте.
struct PillButtonStyle: ButtonStyle {
    var prominent = true
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Typo.inter(15, .semibold))
            .padding(.horizontal, 16).padding(.vertical, 10)
            .foregroundStyle(prominent ? Palette.btnInk : Palette.ink)
            .background(prominent ? Palette.btn : Palette.chip, in: Capsule())
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

/// Чип-переключатель, как «Светлая / Тёмная / Система» на сайте.
struct ChipPicker<Value: Hashable & Identifiable>: View {
    let options: [Value]
    @Binding var selection: Value
    let title: (Value) -> String

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options) { option in
                let on = option == selection
                Button { withAnimation(.easeOut(duration: 0.15)) { selection = option } } label: {
                    Text(title(option))
                        .font(Typo.inter(14, on ? .semibold : .medium))
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                        .foregroundStyle(on ? Palette.btnInk : Palette.ink2)
                        .background(on ? Palette.btn : Color.clear, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(4)
        .background(Palette.chip, in: Capsule())
    }
}
