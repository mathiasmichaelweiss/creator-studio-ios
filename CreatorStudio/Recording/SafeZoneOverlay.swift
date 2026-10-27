import SwiftUI

/// Безопасная зона Reels (кадр 1080×1920): сверху ~220 px под шапку,
/// снизу ~420 px под подпись и кнопки, справа ~120 px под лайки и комментарии.
struct SafeZoneOverlay: View {
    static let top: CGFloat = 220 / 1920
    static let bottom: CGFloat = 420 / 1920
    static let right: CGFloat = 120 / 1080

    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            let rect = CGRect(x: 0, y: h * Self.top,
                              width: w * (1 - Self.right),
                              height: h * (1 - Self.top - Self.bottom))
            Path { $0.addRect(rect) }
                .stroke(Theme.safeZone.opacity(0.9), style: StrokeStyle(lineWidth: 1.5, dash: [8, 6]))
        }
        .allowsHitTesting(false)
    }
}
