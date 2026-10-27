import SwiftUI

/// Текст суфлёра узкой колонкой у верхнего края, рядом с фронтальной камерой,
/// чтобы взгляд оставался почти в объективе. Текст только на экране, в запись не попадает.
///
/// Зона чтения: строка на уровне оранжевой метки яркая, всё выше гаснет
/// (уже прочитано), всё ниже приглушено (ещё впереди). Глаза держатся на одной
/// высоте, текст сам подъезжает к ним.
struct PrompterView: View {
    @EnvironmentObject var settings: PrompterSettings
    @ObservedObject var engine: PrompterEngine
    let height: CGFloat

    /// Где стоит линия чтения, доля высоты окна суфлёра.
    static let readingLine: CGFloat = 0.35

    var body: some View {
        let fs = CGFloat(settings.prompterFontSize)
        let lineY: CGFloat = height * Self.readingLine
        let lineH: CGFloat = fs * 1.25

        GeometryReader { geo in
            Text(settings.script)
                .font(Typo.interFixed(fs, .semibold))
                .foregroundStyle(Palette.ink)
                .lineSpacing(fs * 0.25)
                .multilineTextAlignment(.leading)
                // Текст любой длины: высоту не ограничиваем, иначе SwiftUI обрежет его «…».
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: geo.size.width, alignment: .topLeading)
                .offset(y: lineY - CGFloat(engine.offset))
                
        }
        .padding(.horizontal, 18)
        .frame(height: height)
        .clipped()
        .mask(ReadingMask(lineY: lineY, lineHeight: lineH, height: height))
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(alignment: .topLeading) {
            // Метка-стрелка слева от строки, которую читаешь сейчас.
            Image(systemName: "arrowtriangle.right.fill")
                .font(.system(size: fs * 0.55))
                .foregroundStyle(Theme.accent)
                .offset(x: 2, y: lineY + lineH * 0.5 - fs * 0.3)
                .accessibilityHidden(true)
        }
        .gesture(DragGesture().onChanged { v in
            engine.nudge(by: -v.translation.height / 8)
        })
        .accessibilityLabel("Текст суфлёра")
    }
}

/// Прозрачность по высоте: сверху почти невидимо, строка чтения полностью яркая, ниже приглушено.
struct ReadingMask: View {
    let lineY: CGFloat
    let lineHeight: CGFloat
    let height: CGFloat

    var body: some View {
        LinearGradient(stops: ReadingMask.stops(lineY: lineY, lineHeight: lineHeight, height: height),
                       startPoint: .top, endPoint: .bottom)
    }

    static func stops(lineY: CGFloat, lineHeight: CGFloat, height: CGFloat) -> [Gradient.Stop] {
        guard height > 0 else { return [.init(color: .white, location: 0)] }
        func loc(_ y: CGFloat) -> CGFloat { min(max(y / height, 0), 1) }
        return [
            .init(color: .white.opacity(0.08), location: 0),
            .init(color: .white.opacity(0.25), location: loc(lineY - lineHeight * 0.6)),
            .init(color: .white, location: loc(lineY - lineHeight * 0.1)),
            .init(color: .white, location: loc(lineY + lineHeight * 1.05)),
            .init(color: .white.opacity(0.5), location: loc(lineY + lineHeight * 1.6)),
            .init(color: .white.opacity(0.35), location: 1)
        ]
    }
}
