import AVFoundation
import SwiftUI

struct RecordScreen: View {
    @EnvironmentObject var settings: PrompterSettings
    @StateObject private var recorder = Recorder()
    @StateObject private var engine = PrompterEngine()
    @State private var countdown: Int?
    @State private var showScript = false
    @State private var showSettings = false
    @State private var permissionDenied = false
    @State private var cardIndex = 0

    var body: some View {
        GeometryReader { geo in
            ZStack {
                CameraPreview(session: recorder.session).ignoresSafeArea()
                if settings.showSafeZone { SafeZoneOverlay().ignoresSafeArea() }

                VStack(spacing: 0) {
                    if settings.mode == .prompter {
                        PrompterView(engine: engine, height: geo.size.height * 0.30)
                            .padding(.horizontal, 28)
                    } else {
                        CardsView(index: $cardIndex, height: geo.size.height * 0.34)
                            .padding(.horizontal, 16)
                            .padding(.top, 54)
                    }
                    Spacer()
                    controls
                }

                if let countdown {
                    Text("\(countdown)")
                        .font(Typo.interFixed(120, .bold))
                        .foregroundStyle(Palette.ink)
                        .frame(width: 180, height: 180)
                        .background(Theme.panel, in: Circle())
                        .transition(.scale.combined(with: .opacity))
                        .accessibilityLabel("Отсчёт \(countdown)")
                }
            }
        }
        .task { await setup() }
        .onChange(of: settings.speed) { _, v in engine.speed = v }
        .sheet(isPresented: $showScript) { ScriptEditor() }
        .sheet(isPresented: $showSettings) { SettingsSheet() }
        .alert("Ошибка", isPresented: Binding(get: { recorder.lastError != nil }, set: { if !$0 { recorder.lastError = nil } })) {
            Button("Ок", role: .cancel) {}
        } message: { Text(recorder.lastError ?? "") }
        .sheet(isPresented: Binding(get: { recorder.lastSavedMarkers != nil }, set: { if !$0 { recorder.clearSavedMarkers() } })) {
            SavedSheet(markers: recorder.lastSavedMarkers ?? [])
        }
        .alert("Нужен доступ к камере и микрофону", isPresented: $permissionDenied) {
            Button("Открыть настройки") { UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!) }
            Button("Позже", role: .cancel) {}
        }
        .persistentSystemOverlays(.hidden)
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
    }

    // MARK: Кнопки

    private var controls: some View {
        VStack(spacing: 12) {
            if recorder.state == .idle {
                ChipPicker(options: ReadingMode.allCases, selection: $settings.mode) { $0.title }
                    .frame(maxWidth: 260)
            }
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    if recorder.state == .recording { Circle().fill(Palette.brand).frame(width: 8, height: 8) }
                    Text(timeString(recorder.elapsed))
                        .font(Typo.inter(15, .semibold).monospacedDigit())
                }
                .padding(.horizontal, 12).padding(.vertical, 7)
                .foregroundStyle(recorder.state == .recording ? Color.white : Palette.ink)
                .background(recorder.state == .recording ? AnyShapeStyle(Palette.brand) : AnyShapeStyle(Theme.panel), in: Capsule())
                if !recorder.markers.isEmpty {
                    Text("Повторов: \(recorder.markers.count)")
                        .font(Typo.inter(13, .medium))
                        .padding(.horizontal, 10).padding(.vertical, 7)
                        .foregroundStyle(Palette.ink)
                        .background(Theme.panel, in: Capsule())
                }
                Spacer()
                Text(recorder.formatDescription)
                    .font(Typo.inter(12, .medium))
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .foregroundStyle(Palette.ink2)
                    .background(Theme.panel, in: Capsule())
            }
            HStack {
                circleButton("text.alignleft", label: "Сценарий") { showScript = true }
                    .disabled(recorder.state != .idle)
                Spacer()
                circleButton("arrow.uturn.backward", label: "Повтор") { recorder.markRetake() }
                    .disabled(recorder.state == .idle)
                Spacer()
                mainButton
                Spacer()
                circleButton("stop.fill", label: "Стоп") { stop() }
                    .disabled(recorder.state == .idle || recorder.state == .finishing)
                Spacer()
                circleButton("slider.horizontal.3", label: "Настройки") { showSettings = true }
                    .disabled(recorder.state != .idle)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(Theme.panel, in: RoundedRectangle(cornerRadius: Radius.block, style: .continuous))
        }
        .padding(.horizontal, 16).padding(.bottom, 18)
    }

    private var mainButton: some View {
        Button(action: mainTap) {
            ZStack {
                Circle().stroke(Palette.ink, lineWidth: 3).frame(width: 76, height: 76)
                switch recorder.state {
                case .recording:
                    Image(systemName: "pause.fill").font(.system(size: 28, weight: .bold)).foregroundStyle(Palette.ink)
                case .paused:
                    Palette.brandGradient.frame(width: 62, height: 62).clipShape(Circle())
                        .overlay(Image(systemName: "play.fill").font(.system(size: 24, weight: .bold)).foregroundStyle(.white))
                case .finishing:
                    ProgressView().tint(Palette.ink)
                case .idle:
                    Palette.brandGradient.frame(width: 62, height: 62).clipShape(Circle())
                }
            }
        }
        .disabled(countdown != nil || recorder.state == .finishing)
        .accessibilityLabel(recorder.state == .recording ? "Пауза" : recorder.state == .paused ? "Продолжить" : "Запись")
    }

    private func circleButton(_ icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 17, weight: .semibold))
                .frame(width: 46, height: 46)
                .foregroundStyle(Palette.ink)
                .background(Palette.chip, in: Circle())
        }
        .buttonStyle(DimWhenDisabled())
        .accessibilityLabel(label)
    }

    // MARK: Логика

    private func mainTap() {
        switch recorder.state {
        case .idle:
            engine.reset(); engine.speed = settings.speed
            runCountdown { recorder.start(); if prompting { engine.start() } }
        case .recording:
            // Одна кнопка: стоп записи и стоп текста одновременно.
            recorder.pause(); engine.stop()
        case .paused:
            runCountdown { recorder.resume(); if prompting { engine.start() } }
        case .finishing:
            break
        }
    }

    /// Текст едет только в режиме суфлёра. В карточках листаешь сам.
    private var prompting: Bool { settings.mode == .prompter }

    private func stop() {
        engine.stop()
        recorder.stop()
    }

    private func runCountdown(then action: @escaping () -> Void) {
        let total = max(0, settings.countdown)
        guard total > 0 else { action(); return }
        Task { @MainActor in
            for n in stride(from: total, through: 1, by: -1) {
                withAnimation(.spring) { countdown = n }
                try? await Task.sleep(for: .seconds(1))
            }
            withAnimation { countdown = nil }
            action()
        }
    }

    private func setup() async {
        let video = await AVCaptureDevice.requestAccess(for: .video)
        let audio = await AVCaptureDevice.requestAccess(for: .audio)
        guard video && audio else { permissionDenied = true; return }
        engine.speed = settings.speed
        recorder.configure()
    }

    private func timeString(_ t: TimeInterval) -> String {
        let s = Int(t); return String(format: "%02d:%02d", s / 60, s % 60)
    }
}

/// Кнопка бледнеет, когда недоступна (иначе неясно, почему не нажимается).
private struct DimWhenDisabled: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.35)
    }
}

/// После сохранения: ролик в галерее и список маркеров «повтор».
private struct SavedSheet: View {
    let markers: [TimeInterval]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "checkmark").font(.system(size: 15, weight: .bold))
                    .frame(width: 30, height: 30)
                    .foregroundStyle(Palette.okInk)
                    .background(Palette.okBg, in: Circle())
                Text("Видео сохранено в галерею").font(Typo.inter(18, .semibold))
            }
            if !markers.isEmpty {
                Text("Метки «повтор»: здесь были оговорки")
                    .font(Typo.inter(14, .medium)).foregroundStyle(Palette.ink2)
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(Array(markers.enumerated()), id: \.offset) { i, t in
                            HStack {
                                Text("\(i + 1)").font(Typo.inter(14, .semibold)).foregroundStyle(Palette.ink3)
                                Text(String(format: "%02d:%02d", Int(t) / 60, Int(t) % 60))
                                    .font(Typo.inter(16, .semibold).monospacedDigit())
                                Spacer()
                            }
                            .padding(.horizontal, 14).padding(.vertical, 10)
                            .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.field, style: .continuous))
                        }
                    }
                }
            }
            Spacer(minLength: 0)
            Button("Закрыть") { dismiss() }
                .buttonStyle(PillButtonStyle())
                .frame(maxWidth: .infinity)
        }
        .foregroundStyle(Palette.ink)
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Palette.bg)
        .presentationDetents([.medium])
    }
}
