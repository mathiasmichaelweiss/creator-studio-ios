import SwiftUI

/// Текст суфлёра узкой колонкой у верхнего края, рядом с фронтальной камерой,
/// чтобы взгляд оставался почти в объективе. Текст только на экране, в запись не попадает.
struct PrompterView: View {
    @EnvironmentObject var settings: PrompterSettings
    @ObservedObject var engine: PrompterEngine
    let height: CGFloat

    var body: some View {
        GeometryReader { geo in
            Text(settings.script)
                .font(.system(size: settings.fontSize, weight: .semibold))
                .foregroundStyle(.white)
                .lineSpacing(settings.fontSize * 0.25)
                .multilineTextAlignment(.leading)
                .frame(width: geo.size.width, alignment: .topLeading)
                .offset(y: height * 0.35 - engine.offset)
                .shadow(color: .black.opacity(0.8), radius: 3)
        }
        .frame(height: height)
        .clipped()
        .background(LinearGradient(colors: [.black.opacity(0.65), .black.opacity(0.35)], startPoint: .top, endPoint: .bottom))
        .overlay(alignment: .top) {
            // Линия чтения: здесь глаза должны быть, когда произносишь строку.
            Rectangle().fill(Theme.accent.opacity(0.7)).frame(height: 2).offset(y: height * 0.35 - 4)
        }
        .gesture(DragGesture().onChanged { v in
            engine.nudge(by: -v.translation.height / 8)
        })
        .accessibilityLabel("Текст суфлёра")
    }
}
