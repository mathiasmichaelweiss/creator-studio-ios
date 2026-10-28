import AVFoundation
import AVKit
import SwiftUI

/// Превью фронтальной камеры на весь экран.
/// Здесь же ловится аппаратная кнопка съёмки (DJI Mic, кнопки громкости):
/// iOS отдаёт её только видимому полноэкранному виду, к которому привязана камера.
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    var onCaptureButton: (() -> Void)? = nil

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> PreviewView {
        let v = PreviewView()
        v.previewLayer.session = session
        v.previewLayer.videoGravity = .resizeAspectFill
        v.isUserInteractionEnabled = true
        context.coordinator.onPress = onCaptureButton
        if #available(iOS 17.2, *) {
            let coordinator = context.coordinator
            let interaction = AVCaptureEventInteraction { event in
                if CaptureButtonGate.shouldFire(phase: event.phase == .ended ? .ended
                                                : event.phase == .began ? .began : .cancelled) {
                    coordinator.onPress?()
                }
            }
            interaction.isEnabled = true
            v.addInteraction(interaction)
        }
        return v
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        context.coordinator.onPress = onCaptureButton
    }

    final class Coordinator { var onPress: (() -> Void)? }

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}

/// Чистая логика: на какую фазу нажатия реагировать (на отпускание, как системная камера).
enum CaptureButtonGate {
    enum Phase { case began, ended, cancelled }
    static func shouldFire(phase: Phase) -> Bool { phase == .ended }
}
