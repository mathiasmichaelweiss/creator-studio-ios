import SwiftUI

/// Режим «Карточки»: один абзац на экране. Прочитал про себя, нажал запись,
/// пересказал своими словами, пауза, следующая карточка.
struct CardsView: View {
    @EnvironmentObject var settings: PrompterSettings
    @Binding var index: Int
    let height: CGFloat

    private var cards: [String] { Paragraphs.split(settings.script) }

    var body: some View {
        let list = cards
        let i = Paragraphs.clamp(index, count: list.count)
        let fs = CGFloat(settings.fontSize)

        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(list.isEmpty ? "Нет текста" : "Карточка \(i + 1) из \(list.count)")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                Spacer()
                ProgressDots(count: list.count, current: i)
            }
            ScrollView {
                Text(list.isEmpty ? "Вставь сценарий кнопкой слева внизу. Абзацы раздели пустой строкой." : list[i])
                    .font(.system(size: fs, weight: .semibold))
                    .foregroundStyle(.white)
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
        .padding(16)
        .frame(height: height)
        .background(Color.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 22))
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 30).onEnded { v in
            if v.translation.width < -40 { go(i + 1, count: list.count) }
            if v.translation.width > 40 { go(i - 1, count: list.count) }
        })
        .onChange(of: settings.script) { _, _ in index = 0 }
    }

    private func go(_ new: Int, count: Int) {
        let target = Paragraphs.clamp(new, count: count)
        guard target != index else { return }
        withAnimation(.easeOut(duration: 0.22)) { index = target }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func navButton(_ icon: String, label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 20, weight: .bold)).foregroundStyle(.white)
                .frame(width: 54, height: 44)
                .background(enabled ? Theme.accent : Color.white.opacity(0.15), in: Capsule())
        }
        .disabled(!enabled)
        .accessibilityLabel(label)
    }
}

private struct ProgressDots: View {
    let count: Int
    let current: Int
    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<min(count, 12), id: \.self) { k in
                Capsule().fill(k == current ? Theme.accent : Color.white.opacity(0.3))
                    .frame(width: k == current ? 16 : 6, height: 6)
            }
        }
        .accessibilityHidden(true)
    }
}
