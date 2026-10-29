import AVFoundation
import Photos
import UIKit

/// Камера + микрофон → один файл через AVAssetWriter с поддержкой паузы.
final class Recorder: NSObject, ObservableObject {
    enum State: Equatable { case idle, recording, paused, finishing }

    @Published private(set) var state: State = .idle
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var markers: [TimeInterval] = []
    @Published private(set) var formatDescription = ""
    @Published var lastError: String?
    @Published private(set) var lastSavedMarkers: [TimeInterval]?

    let session = AVCaptureSession()

    private let sessionQueue = DispatchQueue(label: "studio.session")
    private let dataQueue = DispatchQueue(label: "studio.data")
    private let videoOutput = AVCaptureVideoDataOutput()
    private let audioOutput = AVCaptureAudioDataOutput()

    // Состояние ниже трогаем только на dataQueue.
    private var writer: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?
    private var timeline = PausableTimeline()
    private var sessionStarted = false
    private var lastVideoPTS: CMTime = .invalid
    /// Время первого кадра в файле: от него считается таймер записи.
    private var fileStart: CMTime = .zero
    private var outputURL: URL?
    private var videoSize = CGSize(width: 1080, height: 1920)
    private var isWriting = false

    /// Звук микрофона для суфлёра по голосу. Вызывается на очереди камеры.
    private let tapLock = NSLock()
    private var _audioTap: ((CMSampleBuffer) -> Void)?
    var audioTap: ((CMSampleBuffer) -> Void)? {
        get { tapLock.lock(); defer { tapLock.unlock() }; return _audioTap }
        set { tapLock.lock(); _audioTap = newValue; tapLock.unlock() }
    }

    // MARK: Настройка

    func configure() {
        sessionQueue.async { [weak self] in self?.setupSession() }
    }

    private func setupSession() {
        session.beginConfiguration()
        session.sessionPreset = .inputPriority

        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
              let videoIn = try? AVCaptureDeviceInput(device: camera),
              session.canAddInput(videoIn) else {
            publishError("Не удалось открыть фронтальную камеру")
            session.commitConfiguration(); return
        }
        session.addInput(videoIn)
        let chosen = Self.applyBestFormat(to: camera)

        if let mic = AVCaptureDevice.default(for: .audio),
           let audioIn = try? AVCaptureDeviceInput(device: mic),
           session.canAddInput(audioIn) {
            session.addInput(audioIn)
        }

        videoOutput.alwaysDiscardsLateVideoFrames = false
        videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange]
        videoOutput.setSampleBufferDelegate(self, queue: dataQueue)
        if session.canAddOutput(videoOutput) { session.addOutput(videoOutput) }
        audioOutput.setSampleBufferDelegate(self, queue: dataQueue)
        if session.canAddOutput(audioOutput) { session.addOutput(audioOutput) }

        if let conn = videoOutput.connection(with: .video) {
            if conn.isVideoRotationAngleSupported(90) { conn.videoRotationAngle = 90 }
            if conn.isVideoMirroringSupported { conn.automaticallyAdjustsVideoMirroring = false; conn.isVideoMirrored = true }
            if conn.isVideoStabilizationSupported { conn.preferredVideoStabilizationMode = .standard }
        }
        session.commitConfiguration()
        session.startRunning()

        if let chosen {
            let d = CMVideoFormatDescriptionGetDimensions(chosen.format.formatDescription)
            // Портрет: ширина и высота меняются местами.
            dataQueue.async { self.videoSize = CGSize(width: Int(d.height), height: Int(d.width)) }
            DispatchQueue.main.async { self.formatDescription = "\(d.width)×\(d.height) · \(Int(chosen.fps)) fps" }
        }
    }

    /// Лучший видеоформат 16:9 фронтальной камеры: сначала максимум fps (до 60), потом разрешение.
    /// Фотоформаты 4:3 (например 4032×3024) не берём: они не дают вертикальное видео под Reels.
    private static func applyBestFormat(to device: AVCaptureDevice) -> (format: AVCaptureDevice.Format, fps: Double)? {
        let candidates = device.formats.compactMap { f -> (AVCaptureDevice.Format, Int32, Double)? in
            let d = CMVideoFormatDescriptionGetDimensions(f.formatDescription)
            guard FormatPicker.isSixteenByNine(width: d.width, height: d.height) else { return nil }
            let maxFPS = f.videoSupportedFrameRateRanges.map(\.maxFrameRate).max() ?? 0
            guard maxFPS >= 24 else { return nil }
            return (f, d.width * d.height, min(maxFPS, 60))
        }
        guard let best = candidates.max(by: { FormatPicker.isWorse(($0.2, $0.1), than: ($1.2, $1.1)) }) else { return nil }
        do {
            try device.lockForConfiguration()
            device.activeFormat = best.0
            let duration = CMTime(value: 1, timescale: CMTimeScale(best.2))
            device.activeVideoMinFrameDuration = duration
            device.activeVideoMaxFrameDuration = duration
            device.unlockForConfiguration()
            return (best.0, best.2)
        } catch { return nil }
    }

    // MARK: Управление

    func start() {
        guard state == .idle else { return }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("take-\(UUID().uuidString).mov")
        dataQueue.async { [weak self] in
            guard let self else { return }
            do {
                let w = try AVAssetWriter(outputURL: url, fileType: .mov)
                let vSettings: [String: Any] = [
                    AVVideoCodecKey: AVVideoCodecType.hevc,
                    AVVideoWidthKey: Int(self.videoSize.width),
                    AVVideoHeightKey: Int(self.videoSize.height),
                    AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: Int(self.videoSize.width * self.videoSize.height * 12)]
                ]
                let vIn = AVAssetWriterInput(mediaType: .video, outputSettings: vSettings)
                vIn.expectsMediaDataInRealTime = true
                let aSettings: [String: Any] = [
                    AVFormatIDKey: kAudioFormatMPEG4AAC, AVNumberOfChannelsKey: 1,
                    AVSampleRateKey: 48_000, AVEncoderBitRateKey: 192_000
                ]
                let aIn = AVAssetWriterInput(mediaType: .audio, outputSettings: aSettings)
                aIn.expectsMediaDataInRealTime = true
                guard w.canAdd(vIn), w.canAdd(aIn) else { throw RecorderError.writerSetup }
                w.add(vIn); w.add(aIn)
                guard w.startWriting() else { throw w.error ?? RecorderError.writerSetup }
                self.writer = w; self.videoInput = vIn; self.audioInput = aIn
                self.timeline = PausableTimeline(); self.sessionStarted = false; self.lastVideoPTS = .invalid
                self.outputURL = url; self.isWriting = true
                DispatchQueue.main.async { self.markers = []; self.elapsed = 0; self.state = .recording }
            } catch {
                self.publishError("Не удалось начать запись: \(error.localizedDescription)")
            }
        }
    }

    func pause() {
        guard state == .recording else { return }
        dataQueue.async { self.timeline.pause() }
        state = .paused
    }

    func resume() {
        guard state == .paused else { return }
        dataQueue.async { self.timeline.resume() }
        state = .recording
    }

    /// Маркер «повтор» на текущем времени записи.
    func markRetake() {
        guard state == .recording || state == .paused else { return }
        markers.append(elapsed)
    }

    func stop() {
        guard state == .recording || state == .paused else { return }
        state = .finishing
        let savedMarkers = markers
        dataQueue.async { [weak self] in
            guard let self, let w = self.writer else { return }
            self.isWriting = false
            self.videoInput?.markAsFinished(); self.audioInput?.markAsFinished()
            guard self.sessionStarted else {
                w.cancelWriting(); self.reset(); return
            }
            w.finishWriting {
                let url = self.outputURL
                self.dataQueue.async { self.reset() }
                guard w.status == .completed, let url else {
                    self.publishError("Не удалось сохранить файл: \(w.error?.localizedDescription ?? "неизвестно")")
                    return
                }
                Self.saveToPhotos(url) { ok in
                    DispatchQueue.main.async {
                        if ok { self.lastSavedMarkers = savedMarkers } else { self.lastError = "Нет доступа к галерее. Разреши в Настройках." }
                    }
                }
            }
        }
    }

    /// Выбросить текущий дубль без сохранения: файл удаляется, состояние снова «готов».
    func discard() {
        guard state == .recording || state == .paused else { return }
        state = .finishing
        dataQueue.async { [weak self] in
            guard let self else { return }
            self.isWriting = false
            self.writer?.cancelWriting()
            if let url = self.outputURL { try? FileManager.default.removeItem(at: url) }
            self.outputURL = nil
            self.reset()
            DispatchQueue.main.async { self.markers = []; self.elapsed = 0 }
        }
    }

    func clearSavedMarkers() { lastSavedMarkers = nil }

    private func reset() {
        writer = nil; videoInput = nil; audioInput = nil; sessionStarted = false
        DispatchQueue.main.async { self.state = .idle }
    }

    private static func saveToPhotos(_ url: URL, completion: @escaping (Bool) -> Void) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else { completion(false); return }
            PHPhotoLibrary.shared().performChanges({
                PHAssetCreationRequest.forAsset().addResource(with: .video, fileURL: url, options: nil)
            }) { ok, _ in
                try? FileManager.default.removeItem(at: url)
                completion(ok)
            }
        }
    }

    private func publishError(_ message: String) {
        DispatchQueue.main.async { self.lastError = message; if self.state != .idle { self.state = .idle } }
    }

    enum RecorderError: Error { case writerSetup }
}

// MARK: Сэмплы

extension Recorder: AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        if output === audioOutput { audioTap?(sampleBuffer) }
        guard isWriting, let writer, writer.status == .writing else { return }
        let isVideo = output === videoOutput
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let dur = CMSampleBufferGetDuration(sampleBuffer)
        guard let mapped = timeline.map(presentation: pts, duration: dur) else { return }

        if !sessionStarted {
            guard isVideo else { return } // начинаем файл с кадра, не со звука
            writer.startSession(atSourceTime: mapped)
            fileStart = mapped
            sessionStarted = true
        }
        guard let retimed = Self.retime(sampleBuffer, to: mapped) else { return }

        if isVideo {
            if let v = videoInput, v.isReadyForMoreMediaData, mapped > lastVideoPTS || !lastVideoPTS.isValid {
                v.append(retimed); lastVideoPTS = mapped
                let seconds = CMTimeSubtract(mapped, fileStart).seconds
                DispatchQueue.main.async { self.elapsed = seconds }
            }
        } else if let a = audioInput, a.isReadyForMoreMediaData {
            a.append(retimed)
        }
    }

    /// Сдвигает все тайминги буфера так, чтобы первый сэмпл начинался в `pts`.
    private static func retime(_ buffer: CMSampleBuffer, to pts: CMTime) -> CMSampleBuffer? {
        let delta = CMTimeSubtract(pts, CMSampleBufferGetPresentationTimeStamp(buffer))
        var count: CMItemCount = 0
        CMSampleBufferGetSampleTimingInfoArray(buffer, entryCount: 0, arrayToFill: nil, entriesNeededOut: &count)
        guard count > 0 else { return nil }
        var timings = [CMSampleTimingInfo](repeating: CMSampleTimingInfo(), count: count)
        CMSampleBufferGetSampleTimingInfoArray(buffer, entryCount: count, arrayToFill: &timings, entriesNeededOut: &count)
        for i in timings.indices {
            timings[i].presentationTimeStamp = CMTimeAdd(timings[i].presentationTimeStamp, delta)
            if timings[i].decodeTimeStamp.isValid {
                timings[i].decodeTimeStamp = CMTimeAdd(timings[i].decodeTimeStamp, delta)
            }
        }
        var out: CMSampleBuffer?
        CMSampleBufferCreateCopyWithNewTiming(allocator: kCFAllocatorDefault, sampleBuffer: buffer,
                                              sampleTimingEntryCount: count, sampleTimingArray: &timings,
                                              sampleBufferOut: &out)
        return out
    }
}
