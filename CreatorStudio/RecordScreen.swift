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
                        .font(.system(size: 140, weight: .heavy))
                        .foregroundStyle(.white)
                        .shadow(radius: 12)
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
        VStack(spacing: 14) {
            HStack {
                Text(timeString(recorder.elapsed))
                    .font(.system(.body, design: .monospaced).weight(.semibold))
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(recorder.state == .recording ? Color.red.opacity(0.85) : Theme.panel, in: Capsule())
                Spacer()
                Text(recorder.formatDescription).font(.caption).foregroundStyle(.white.opacity(0.8))
            }
            HStack(spacing: 22) {
                circleButton("text.alignleft", label: "Сценарий") { showScript = true }
                    .disabled(recorder.state != .idle)
                circleButton("arrow.uturn.backward", label: "Повтор") { recorder.markRetake() }
                    .disabled(recorder.state == .idle)
                mainButton
                circleButton("stop.fill", label: "Стоп") { stop() }
                    .disabled(recorder.state == .idle || recorder.state == .finishing)
                circleButton("slider.horizontal.3", label: "Настройки") { showSettings = true }
                    .disabled(recorder.state != .idle)
            }
            if !recorder.markers.isEmpty {
                Text("Повторов: \(recorder.markers.count)").font(.caption).foregroundStyle(.white.opacity(0.8))
            }
        }
        .padding(.horizontal, 20).padding(.bottom, 24)
    }

    private var mainButton: some View {
        Button(action: mainTap) {
            ZStack {
                Circle().stroke(.white, lineWidth: 4).frame(width: 78, height: 78)
                switch recorder.state {
                case .recording:
                    Image(systemName: "pause.fill").font(.system(size: 30)).foregroundStyle(.white)
                case .paused:
                    Image(systemName: "play.fill").font(.system(size: 30)).foregroundStyle(Theme.accent)
                case .finishing:
                    ProgressView().tint(.white)
                case .idle:
                    Circle().fill(Color.red).frame(width: 62, height: 62)
                }
            }
        }
        .disabled(countdown != nil || recorder.state == .finishing)
        .accessibilityLabel(recorder.state == .recording ? "Пауза" : recorder.state == .paused ? "Продолжить" : "Запись")
    }

    private func circleButton(_ icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 18, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 48, height: 48).background(Theme.panel, in: Circle())
        }
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

/// После сохранения: ролик в галерее и список маркеров «повтор».
private struct SavedSheet: View {
    let markers: [TimeInterval]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section { Label("Видео сохранено в галерею", systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
                if !markers.isEmpty {
                    Section("Метки «повтор»: здесь были оговорки") {
                        ForEach(Array(markers.enumerated()), id: \.offset) { i, t in
                            Text("\(i + 1). \(String(format: "%02d:%02d", Int(t) / 60, Int(t) % 60))")
                                .font(.system(.body, design: .monospaced))
                        }
                    }
                }
            }
            .navigationTitle("Готово")
            .toolbar { Button("Закрыть") { dismiss() } }
        }
        .presentationDetents([.medium])
    }
}
