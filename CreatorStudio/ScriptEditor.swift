import SwiftUI

/// Временный ввод текста. На этапе 2 сценарии придут из Notion.
struct ScriptEditor: View {
    @EnvironmentObject var settings: PrompterSettings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SheetHeader(title: "Сценарий") { dismiss() }
            Text("Абзацы раздели пустой строкой: в режиме «Карточки» каждый абзац станет отдельной карточкой.")
                .font(Typo.inter(14, relativeTo: .footnote))
                .foregroundStyle(Palette.ink2)
            TextEditor(text: $settings.script)
                .font(Typo.inter(17))
                .foregroundStyle(Palette.ink)
                .scrollContentBackground(.hidden)
                .padding(12)
                .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.field, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Radius.field, style: .continuous).stroke(Palette.line))
            HStack {
                Button("Вставить из буфера") {
                    if let s = UIPasteboard.general.string { settings.script = s }
                }
                .buttonStyle(PillButtonStyle(prominent: false))
                Spacer()
                Button("Очистить") { settings.script = "" }
                    .buttonStyle(PillButtonStyle(prominent: false))
            }
        }
        .padding(20)
        .background(Palette.bg.ignoresSafeArea())
    }
}

struct SettingsSheet: View {
    @EnvironmentObject var settings: PrompterSettings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                SheetHeader(title: "Настройки") { dismiss() }

                Group {
                    SectionTitle("Режим чтения")
                    ChipPicker(options: ReadingMode.allCases, selection: $settings.mode) { $0.title }
                    Hint(settings.mode == .prompter
                         ? "Текст сам едет во время записи. Читаешь дословно."
                         : "Один абзац на экране. Прочитал, нажал запись, пересказал своими словами, пауза, следующая карточка.")
                }

                Group {
                    SectionTitle("Тема")
                    ChipPicker(options: AppTheme.allCases, selection: $settings.theme) { $0.title }
                    SectionTitle("Размер текста")
                    ChipPicker(options: TextScale.allCases, selection: $settings.textScale) { $0.title }
                }

                Card {
                    if settings.mode == .prompter {
                        SliderRow(title: "Скорость суфлёра", value: $settings.speed, range: 10...150, step: 5)
                        Divider().overlay(Palette.line)
                    }
                    SliderRow(title: "Размер шрифта", value: $settings.fontSize, range: 18...56, step: 1)
                    Divider().overlay(Palette.line)
                    Stepper(value: $settings.countdown, in: 0...5) {
                        Text("Отсчёт перед стартом: \(settings.countdown) с").font(Typo.inter(16, .medium))
                    }
                    Divider().overlay(Palette.line)
                    Toggle(isOn: $settings.showSafeZone) {
                        Text("Безопасная зона Reels").font(Typo.inter(16, .medium))
                    }
                    .tint(Palette.brand)
                }
            }
            .padding(20)
        }
        .foregroundStyle(Palette.ink)
        .background(Palette.bg.ignoresSafeArea())
        .presentationDetents([.medium, .large])
    }
}

// MARK: Мелкие компоненты листов

struct SheetHeader: View {
    let title: String
    let onDone: () -> Void
    var body: some View {
        HStack {
            Text(title).font(Typo.inter(26, .bold, relativeTo: .title)).tracking(-0.5)
            Spacer()
            Button("Готово", action: onDone).buttonStyle(PillButtonStyle())
        }
        .padding(.top, 4)
    }
}

private struct SectionTitle: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(Typo.inter(13, .semibold, relativeTo: .footnote)).foregroundStyle(Palette.ink3)
    }
}

private struct Hint: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(Typo.inter(14, relativeTo: .footnote)).foregroundStyle(Palette.ink2)
    }
}

private struct Card<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 14) { content }
            .padding(16)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).stroke(Palette.line))
    }
}

private struct SliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(Typo.inter(16, .medium))
                Spacer()
                Text("\(Int(value))").font(Typo.inter(16, .semibold).monospacedDigit()).foregroundStyle(Palette.ink2)
            }
            Slider(value: $value, in: range, step: step).tint(Palette.brand)
        }
    }
}
