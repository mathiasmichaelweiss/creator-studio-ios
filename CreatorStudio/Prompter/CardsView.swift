import SwiftUI

/// Режим «Карточки»: один абзац на экране. Прочитал про себя, нажал запись,
/// пересказал своими словами, пауза, следующая карточка.
struct CardsView: View {
    @EnvironmentObject var settings: PrompterSettings
    @Binding var index: Int
    let height: CGFloat
    @State private var showLook = false

    private var cards: [String] { Paragraphs.split(settings.script) }

    var body: some View {
        let list = cards
        let i = Paragraphs.clamp(index, count: list.count)
        let fs = CGFloat(settings.prompterFontSize)

        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(list.isEmpty ? "Нет текста" : "Карточка \(i + 1) из \(list.count)")
                    .font(Typo.inter(13, .semibold, relativeTo: .footnote))
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .foregroundStyle(ink2)
                    .background(Palette.chip, in: Capsule())
                Spacer()
                ProgressDots(count: list.count, current: i)
                Button { showLook = true } label: {
                    Image(systemName: "gearshape.fill").font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(ink2)
                        .frame(width: 34, height: 34)
                        .background(Palette.chip, in: Circle())
                }
                .accessibilityLabel("Вид карточки")
                .popover(isPresented: $showLook) {
                    CardLookPanel().environmentObject(settings).presentationCompactAdaptation(.popover)
                }
            }
            ScrollView {
                Text(list.isEmpty ? "Вставь сценарий кнопкой слева внизу. Абзацы раздели пустой строкой." : list[i])
                    .font(Typo.interFixed(fs, .semibold))
                    .foregroundStyle(ink)
                    .lineSpacing(fs * 0.2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .id(i)
                    .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                            removal: .move(edge: .leading).combined(with: .opacity)))
            }
            .scrollIndicators(.hidden)
            HStack(spacing: 12) {
                navButton("chevron.left", label: "Предыдущая карточка", enabled: i > 0) { go(i - 1, count: list.count) }
                Spacer()
                navButton("chevron.right", label: "Следующая карточка", enabled: i < list.count - 1) { go(i + 1, count: list.count) }
            }
        }
        .padding(18)
        .frame(height: height)
        .background(cardFill, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 30).onEnded { v in
            if v.translation.width < -40 { go(i + 1, count: list.count) }
            if v.translation.width > 40 { go(i - 1, count: list.count) }
        })
        .onChange(of: settings.script) { _, _ in index = 0 }
    }

    private var cardFill: Color {
        (settings.cardTone == .dark ? Color.black : Color.white).opacity(CardLook.clampOpacity(settings.cardOpacity))
    }
    private var ink: Color { settings.cardTone == .dark ? .white : .black }
    private var ink2: Color { ink.opacity(0.7) }

    private func go(_ new: Int, count: Int) {
        let target = Paragraphs.clamp(new, count: count)
        guard target != index else { return }
        withAnimation(.easeOut(duration: 0.22)) { index = target }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func navButton(_ icon: String, label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 18, weight: .bold))
                .foregroundStyle(enabled ? Palette.btnInk : Palette.ink3)
                .frame(width: 56, height: 44)
                .background(enabled ? Palette.btn : Palette.chip, in: Capsule())
        }
        .disabled(!enabled)
        .accessibilityLabel(label)
    }
}

/// Точки прогресса как под каруселью «Важное сегодня» на сайте.
private struct ProgressDots: View {
    let count: Int
    let current: Int
    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<min(count, 12), id: \.self) { k in
                Capsule().fill(k == current ? Palette.ink : Palette.line)
                    .frame(width: k == current ? 16 : 6, height: 6)
            }
        }
        .accessibilityHidden(true)
    }
}

/// Настройки вида карточки: цвет подложки и прозрачность.
private struct CardLookPanel: View {
    @EnvironmentObject var settings: PrompterSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Карточка").font(Typo.inter(16, .semibold))
            ChipPicker(options: CardTone.allCases, selection: $settings.cardTone) { $0.title }
            HStack {
                Text("Непрозрачность").font(Typo.inter(13, .semibold, relativeTo: .footnote)).foregroundStyle(Palette.ink3)
                Spacer()
                Text(CardLook.percent(settings.cardOpacity)).font(Typo.inter(13, .semibold, relativeTo: .footnote))
            }
            Slider(value: $settings.cardOpacity, in: CardLook.minOpacity...1)
                .tint(Palette.brand)
        }
        .padding(18)
        .frame(width: 280)
        .foregroundStyle(Palette.ink)
    }
}
