import SwiftUI

/// Настройки фронтальной камеры: кадр, ориентация, Center Stage, стабилизация, Pro.
struct CameraSheet: View {
    @ObservedObject var recorder: Recorder
    @Environment(\.dismiss) private var dismiss

    private var o: CameraOptions { recorder.options }
    private var caps: CameraCapabilities { recorder.capabilities }
    private var idle: Bool { recorder.state == .idle }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                SheetHeader(title: "Камера") { dismiss() }

                group("Кадр", available: caps.supportsWide && !o.centerStage,
                      hint: o.centerStage ? "При Center Stage кадр выбирает сама камера."
                          : caps.supportsWide ? "«Широко» использует весь квадратный сенсор: в кадр влезает больше комнаты."
                          : "Эта камера шире не умеет.") {
                    ChipPicker(options: CameraOptions.Framing.allCases, selection: bind(\.framing)) { $0.title }
                }

                group("Ориентация", available: caps.supportsHorizontal && idle,
                      hint: !caps.supportsHorizontal ? "Нужен iPhone 17 или новее и iOS 26."
                          : idle ? "Горизонтальное видео, а телефон держишь вертикально."
                          : "Меняется между дублями.") {
                    ChipPicker(options: CameraOptions.Orientation.allCases, selection: bind(\.orientation)) { $0.title }
                }

                group("Center Stage", available: caps.supportsCenterStage,
                      hint: caps.supportsCenterStage ? "Кадр следует за тобой, если ходишь по комнате." : "Недоступно на этой камере.") {
                    Toggle("Следить за мной", isOn: bind(\.centerStage))
                        .font(Typo.inter(16, .medium)).tint(Palette.brand)
                }

                group("Стабилизация", available: caps.supportsUltra,
                      hint: caps.supportsUltra ? "«Ультра» сглаживает тряску сильнее, кадр чуть уже." : "Ультра недоступна на этой камере.") {
                    ChipPicker(options: CameraOptions.Stabilization.allCases, selection: bind(\.stabilization)) { $0.title }
                }

                group("Выдержка (Pro)", available: caps.supportsPro,
                      hint: "Для \(Int(caps.fps)) fps естественное движение: 1/\(CameraMath.recommendedShutter(fps: caps.fps)). Под лампами в Германии (50 Гц) без мерцания: 1/50 или 1/100.") {
                    ChipPicker(options: choices([Int?]([nil]) + CameraMath.shutterOptions(fps: caps.fps).map { Optional($0) }),
                               selection: bindChoice(\.shutter)) { CameraMath.shutterTitle($0.value) }
                }

                if o.shutter == nil {
                    group("Экспозиция", available: true, hint: "Светлее или темнее авто-экспозиции.") {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Компенсация").font(Typo.inter(16, .medium))
                                Spacer()
                                Text(String(format: "%+.1f EV", o.exposureBias))
                                    .font(Typo.inter(16, .semibold).monospacedDigit()).foregroundStyle(Palette.ink2)
                            }
                            Slider(value: bind(\.exposureBias), in: -2...2, step: 0.1).tint(Palette.brand)
                        }
                    }
                }

                group("Баланс белого (Pro)", available: caps.supportsPro,
                      hint: "Тёплые лампы около 3200K, дневной свет у окна около 5600K.") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        ChipPicker(options: choices([Int?]([nil]) + CameraMath.whiteBalanceOptions.map { Optional($0) }),
                                   selection: bindChoice(\.whiteBalance)) { CameraMath.whiteBalanceTitle($0.value) }
                    }
                }

                group("Гистограмма", available: true, hint: "Столбики справа у края: пересвет, слева: слишком темно.") {
                    Toggle("Показывать на экране", isOn: bind(\.showHistogram))
                        .font(Typo.inter(16, .medium)).tint(Palette.brand)
                }
            }
            .padding(20)
        }
        .foregroundStyle(Palette.ink)
        .background(Palette.bg)
    }

    // MARK: Помощники

    private func group<C: View>(_ title: String, available: Bool, hint: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(Typo.inter(13, .semibold, relativeTo: .footnote)).foregroundStyle(Palette.ink3)
            content()
                .disabled(!available)
                .opacity(available ? 1 : 0.4)
            Text(hint).font(Typo.inter(14, relativeTo: .footnote)).foregroundStyle(Palette.ink2)
        }
    }

    private func bind<T>(_ key: WritableKeyPath<CameraOptions, T>) -> Binding<T> {
        Binding(get: { recorder.options[keyPath: key] },
                set: { v in var n = recorder.options; n[keyPath: key] = v; recorder.update(n) })
    }

    private func choices(_ values: [Int?]) -> [IntChoice] { values.map { IntChoice(value: $0) } }

    private func bindChoice(_ key: WritableKeyPath<CameraOptions, Int?>) -> Binding<IntChoice> {
        Binding(get: { IntChoice(value: recorder.options[keyPath: key]) },
                set: { c in var n = recorder.options; n[keyPath: key] = c.value; recorder.update(n) })
    }
}

/// Пункт выбора «Авто или число» для ChipPicker.
struct IntChoice: Hashable, Identifiable {
    let value: Int?
    var id: String { value.map(String.init) ?? "auto" }
}

/// Маленькая гистограмма яркости поверх превью.
struct HistogramView: View {
    let bins: [Double]
    var body: some View {
        HStack(alignment: .bottom, spacing: 1) {
            ForEach(Array(bins.enumerated()), id: \.offset) { _, v in
                Rectangle().fill(Color.white.opacity(0.85))
                    .frame(width: 3, height: max(1, 40 * v))
            }
        }
        .frame(height: 40, alignment: .bottom)
        .padding(8)
        .background(Color.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityLabel("Гистограмма яркости")
    }
}
