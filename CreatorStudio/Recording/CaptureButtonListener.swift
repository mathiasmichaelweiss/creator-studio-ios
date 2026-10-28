import AVKit
import SwiftUI

/// Ловит аппаратную кнопку съёмки: кнопку на DJI Mic (приходит как кнопка громкости),
/// сами кнопки громкости iPhone и кнопку «Камера» на iPhone 16.
/// Срабатывает один раз на отпускание, как спуск в системной камере.
/// Работает только пока AVCaptureSession запущена и приложение на экране.
struct CaptureButtonListener: UIViewRepresentable {
    let onPress: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onPress: onPress) }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = true
        if #available(iOS 17.2, *) {
            let coordinator = context.coordinator
            let interaction = AVCaptureEventInteraction { event in
                if CaptureButtonGate.shouldFire(phase: event.phase.gatePhase) {
                    coordinator.onPress()
                }
            }
            interaction.isEnabled = true
            view.addInteraction(interaction)
        }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.onPress = onPress
    }

    final class Coordinator {
        var onPress: () -> Void
        init(onPress: @escaping () -> Void) { self.onPress = onPress }
    }
}

/// Чистая логика: на какую фазу нажатия реагировать.
enum CaptureButtonGate {
    enum Phase { case began, ended, cancelled }
    static func shouldFire(phase: Phase) -> Bool { phase == .ended }
}

@available(iOS 17.2, *)
private extension AVCaptureEventPhase {
    var gatePhase: CaptureButtonGate.Phase {
        switch self {
        case .began: return .began
        case .ended: return .ended
        default: return .cancelled
        }
    }
}
