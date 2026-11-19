import AVFoundation
import CoreImage
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
    /// Настройки камеры: широкий кадр, ориентация, Center Stage, стабилизация, Pro.
    @Published private(set) var options = CameraOptions.load()
    @Published private(set) var capabilities = CameraCapabilities()
    /// Гистограмма яркости (0…1), если включена.
    @Published private(set) var histogram: [Double] = []
    /// Горизонталь вырезается из высокого кадра (если iOS не умеет 16:9 сам). Для рамки в превью.
    @Published private(set) var cropping = false

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

    // Камера: трогаем на sessionQueue.
    private var camera: AVCaptureDevice?
    /// Если iOS считает соотношение от сенсора, а не от экрана, меняем 16:9 и 9:16 местами.
    private var aspectSwapped = false
    /// Сейчас стоит высокий формат (4:3 или квадрат) для вырезания горизонтали.
    private var tallFormatActive = false

    // Наблюдение за кадрами: трогаем на dataQueue.
    private var frameCounter = 0
    private var framesSinceAspect = 0
    private var desiredOrientation: CameraOptions.Orientation = .vertical
    private var aspectRetried = false
    private var histogramOn = false
    /// Вырезать 16:9 из кадра перед записью.
    private var cropLandscape = false
    private var adaptor: AVAssetWriterInputPixelBufferAdaptor?
    private let ciContext = CIContext(options: [.cacheIntermediates: false])

    /// Звук микрофона для суфлёра по голосу. Вызывается на очереди камеры.
    private let tapLock = NSLock()
    private var _audioTap: ((CMSampleBuffer) -> Void)?
    var audioTap: ((CMSampleBuffer) -> Void)? {
        get { tapLock.lock(); defer { tapLock.unlock() }; return _audioTap }
        set { tapLock.lock(); _audioTap = newValue; tapLock.unlock() }
    }

    // MARK: Настройка

    func configure() {
        let current = options
        sessionQueue.async { [weak self] in
            self?.setupSession()
            self?.applyOptions(current)
        }
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
        let chosen = Self.applyBestFormat(to: camera, tall: false)
        self.camera = camera

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
            // Портрет: ширина и высота меняются местами. Точный размер потом берём из кадров.
            dataQueue.async { self.videoSize = CGSize(width: Int(d.height), height: Int(d.width)) }
            DispatchQueue.main.async { self.formatDescription = "\(d.width)×\(d.height) · \(Int(chosen.fps)) fps" }
        }
        let caps = Self.capabilities(of: camera, fps: chosen?.fps ?? 30)
        DispatchQueue.main.async { self.capabilities = caps }
    }

    // MARK: Настройки камеры

    /// Поменять настройки. Ориентацию меняем только между дублями.
    func update(_ new: CameraOptions) {
        var o = new
        if state != .idle { o.orientation = options.orientation }
        guard o != options else { return }
        options = o
        o.save()
        sessionQueue.async { [weak self] in self?.applyOptions(o) }
    }

    private static func capabilities(of device: AVCaptureDevice, fps: Double) -> CameraCapabilities {
        var c = CameraCapabilities()
        let f = device.activeFormat
        c.fps = fps
        c.supportsWide = CameraMath.supportsWide(minAvailable: Double(device.minAvailableVideoZoomFactor))
        c.supportsCenterStage = f.isCenterStageSupported
        c.supportsUltra = f.isVideoStabilizationModeSupported(.cinematicExtended)
            || f.isVideoStabilizationModeSupported(.cinematic)
        c.supportsPro = device.isExposureModeSupported(.custom)
        c.supportsHorizontal = isDynamic(f) || device.formats.contains(where: isTallVideo)
        return c
    }

    /// Применить все настройки к камере. Только на sessionQueue.
    private func applyOptions(_ o: CameraOptions) {
        guard let device = camera else { return }

        // Горизонталь без «динамического соотношения»: берём высокий формат и вырезаем 16:9 сами.
        let useCrop = o.orientation == .horizontal && !Self.isDynamic(device.activeFormat)
            && (tallFormatActive || device.formats.contains(where: Self.isTallVideo))
        if useCrop != tallFormatActive {
            session.beginConfiguration()
            let chosen = Self.applyBestFormat(to: device, tall: useCrop)
            session.commitConfiguration()
            tallFormatActive = useCrop
            if let chosen {
                let d = CMVideoFormatDescriptionGetDimensions(chosen.format.formatDescription)
                let fps = chosen.fps
                DispatchQueue.main.async {
                    self.formatDescription = "\(d.width)×\(d.height) · \(Int(fps)) fps"
                    self.capabilities.fps = fps
                }
            }
        }
        let cropNow = tallFormatActive
        dataQueue.async { self.cropLandscape = cropNow }
        DispatchQueue.main.async { self.cropping = cropNow }
        let format = device.activeFormat

        // Center Stage: флаг общий для приложения, управляем им сами.
        if format.isCenterStageSupported {
            AVCaptureDevice.centerStageControlMode = .app
            AVCaptureDevice.isCenterStageEnabled = o.centerStage
        }

        if #available(iOS 26.0, *) { applyAspect(o.orientation, device: device) }

        do {
            try device.lockForConfiguration()
            // Зум: при Center Stage кадром управляет система.
            if !(o.centerStage && format.isCenterStageSupported) {
                let z = CameraMath.zoomFactors(minAvailable: Double(device.minAvailableVideoZoomFactor),
                                               maxAvailable: Double(device.maxAvailableVideoZoomFactor))
                device.videoZoomFactor = CGFloat(o.framing == .wide ? z.wide : z.normal)
            }
            // Экспозиция.
            if let s = o.shutter, device.isExposureModeSupported(.custom) {
                let wanted = 1.0 / Double(max(s, 1))
                let seconds = CameraMath.clamp(wanted, format.minExposureDuration.seconds, format.maxExposureDuration.seconds)
                let duration = CMTime(seconds: seconds, preferredTimescale: 1_000_000)
                device.setExposureModeCustom(duration: duration, iso: AVCaptureDevice.currentISO, completionHandler: nil)
            } else {
                if device.isExposureModeSupported(.continuousAutoExposure) { device.exposureMode = .continuousAutoExposure }
                let bias = CameraMath.clamp(o.exposureBias, device.minExposureTargetBias, device.maxExposureTargetBias)
                device.setExposureTargetBias(bias, completionHandler: nil)
            }
            // Баланс белого.
            if let k = o.whiteBalance, device.isWhiteBalanceModeSupported(.locked) {
                let tt = AVCaptureDevice.WhiteBalanceTemperatureAndTintValues(temperature: Float(k), tint: 0)
                var g = device.deviceWhiteBalanceGains(for: tt)
                let m = device.maxWhiteBalanceGain
                g.redGain = CameraMath.clampGain(g.redGain, maxGain: m)
                g.greenGain = CameraMath.clampGain(g.greenGain, maxGain: m)
                g.blueGain = CameraMath.clampGain(g.blueGain, maxGain: m)
                device.setWhiteBalanceModeLocked(with: g, completionHandler: nil)
            } else if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                device.whiteBalanceMode = .continuousAutoWhiteBalance
            }
            device.unlockForConfiguration()
        } catch {
            publishError("Не удалось настроить камеру")
        }

        if let conn = videoOutput.connection(with: .video), conn.isVideoStabilizationSupported {
            conn.preferredVideoStabilizationMode = Self.stabilizationMode(o.stabilization, format: format)
        }

        let orientation = o.orientation
        let histogram = o.showHistogram
        dataQueue.async {
            if self.desiredOrientation != orientation { self.aspectRetried = false; self.framesSinceAspect = 0 }
            self.desiredOrientation = orientation
            self.histogramOn = histogram
        }
        if !histogram { DispatchQueue.main.async { self.histogram = [] } }
    }

    /// Горизонталь без поворота телефона: квадратный сенсор отдаёт кадр 16:9 или 9:16.
    @available(iOS 26.0, *)
    private func applyAspect(_ orientation: CameraOptions.Orientation, device: AVCaptureDevice) {
        let supported = device.activeFormat.supportedDynamicAspectRatios
        guard !supported.isEmpty else { return }
        let landscapeOnScreen = orientation == .horizontal
        // Для iOS соотношение считается от сенсора. Сенсор лежит боком, поэтому по умолчанию наоборот.
        let wantSensorPortrait = aspectSwapped ? !landscapeOnScreen : landscapeOnScreen
        let ratio: AVCaptureDevice.AspectRatio = wantSensorPortrait ? .ratio9x16 : .ratio16x9
        guard supported.contains(ratio) else { return }
        device.setDynamicAspectRatio(ratio, completionHandler: nil)
    }

    private static func stabilizationMode(_ s: CameraOptions.Stabilization,
                                          format: AVCaptureDevice.Format) -> AVCaptureVideoStabilizationMode {
        guard s == .ultra else { return .standard }
        if #available(iOS 18.0, *), format.isVideoStabilizationModeSupported(.cinematicExtendedEnhanced) {
            return .cinematicExtendedEnhanced
        }
        if format.isVideoStabilizationModeSupported(.cinematicExtended) { return .cinematicExtended }
        if format.isVideoStabilizationModeSupported(.cinematic) { return .cinematic }
        return .standard
    }

    /// Каждый кадр видео (на dataQueue): размер для записи, проверка ориентации, гистограмма.
    private func observe(_ buffer: CMSampleBuffer) {
        guard let px = CMSampleBufferGetImageBuffer(buffer) else { return }
        frameCounter += 1
        let w = CVPixelBufferGetWidth(px), h = CVPixelBufferGetHeight(px)
        if !isWriting {
            if cropLandscape {
                let r = CameraMath.landscapeCrop(width: w, height: h)
                videoSize = CGSize(width: r.w, height: r.h)
            } else {
                videoSize = CGSize(width: w, height: h)
            }
            framesSinceAspect += 1
            // Через секунду кадр всё ещё не той ориентации: значит iOS считает соотношение наоборот.
            if framesSinceAspect == 60, !aspectRetried, !cropLandscape,
               !CameraMath.matches(desiredOrientation, width: w, height: h) {
                aspectRetried = true
                let wanted = desiredOrientation
                sessionQueue.async { [weak self] in
                    guard let self, let device = self.camera else { return }
                    self.aspectSwapped.toggle()
                    if #available(iOS 26.0, *) { self.applyAspect(wanted, device: device) }
                }
            }
        }
        if histogramOn, frameCounter % 15 == 0 {
            let bins = Self.histogram(px)
            DispatchQueue.main.async { self.histogram = bins }
        }
    }

    private static func histogram(_ px: CVPixelBuffer) -> [Double] {
        CVPixelBufferLockBaseAddress(px, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(px, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddressOfPlane(px, 0) else { return [] }
        let w = CVPixelBufferGetWidthOfPlane(px, 0)
        let h = CVPixelBufferGetHeightOfPlane(px, 0)
        let row = CVPixelBufferGetBytesPerRowOfPlane(px, 0)
        let p = base.assumingMemoryBound(to: UInt8.self)
        return CameraMath.histogram(width: w, height: h, step: 12, bins: 32) { x, y in p[y * row + x] }
    }

    /// Лучший видеоформат 16:9 фронтальной камеры: сначала максимум fps (до 60), потом разрешение.
    /// Фотоформаты 4:3 (например 4032×3024) не берём: они не дают вертикальное видео под Reels.
    private static func applyBestFormat(to device: AVCaptureDevice, tall: Bool) -> (format: AVCaptureDevice.Format, fps: Double)? {
        // iPhone 17/18: форматы с «динамическим соотношением» умеют и 9:16, и 16:9. Если такие есть, берём их.
        let dynamicOnly = device.formats.contains(where: isDynamic)
        let candidates = device.formats.compactMap { f -> (AVCaptureDevice.Format, Int32, Double)? in
            let d = CMVideoFormatDescriptionGetDimensions(f.formatDescription)
            if tall {
                guard isTallVideo(f) else { return nil }
            } else if dynamicOnly {
                guard isDynamic(f) else { return nil }
            } else {
                guard FormatPicker.isSixteenByNine(width: d.width, height: d.height) else { return nil }
            }
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

    /// Высокий видеоформат (4:3 или квадрат) от 30 fps: из него вырезается горизонталь 16:9.
    private static func isTallVideo(_ f: AVCaptureDevice.Format) -> Bool {
        let d = CMVideoFormatDescriptionGetDimensions(f.formatDescription)
        let maxFPS = f.videoSupportedFrameRateRanges.map(\.maxFrameRate).max() ?? 0
        return FormatPicker.isTall(width: d.width, height: d.height) && maxFPS >= 30
    }

    private static func isDynamic(_ f: AVCaptureDevice.Format) -> Bool {
        if #available(iOS 26.0, *) { return !f.supportedDynamicAspectRatios.isEmpty }
        return false
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
                var ad: AVAssetWriterInputPixelBufferAdaptor?
                if self.cropLandscape {
                    ad = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: vIn, sourcePixelBufferAttributes: [
                        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                        kCVPixelBufferWidthKey as String: Int(self.videoSize.width),
                        kCVPixelBufferHeightKey as String: Int(self.videoSize.height)
                    ])
                }
                w.add(vIn); w.add(aIn)
                guard w.startWriting() else { throw w.error ?? RecorderError.writerSetup }
                self.writer = w; self.videoInput = vIn; self.audioInput = aIn; self.adaptor = ad
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
        writer = nil; videoInput = nil; audioInput = nil; adaptor = nil; sessionStarted = false
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
        let isVideo = output === videoOutput
        if isVideo { observe(sampleBuffer) }
        guard isWriting, let writer, writer.status == .writing else { return }
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let dur = CMSampleBufferGetDuration(sampleBuffer)
        guard let mapped = timeline.map(presentation: pts, duration: dur) else { return }

        if !sessionStarted {
            guard isVideo else { return } // начинаем файл с кадра, не со звука
            writer.startSession(atSourceTime: mapped)
            fileStart = mapped
            sessionStarted = true
        }
        if isVideo, let ad = adaptor {
            // Горизонталь: вырезаем 16:9 из высокого кадра.
            if let v = videoInput, v.isReadyForMoreMediaData, mapped > lastVideoPTS || !lastVideoPTS.isValid,
               let src = CMSampleBufferGetImageBuffer(sampleBuffer), let pool = ad.pixelBufferPool,
               let px = cropped(src, pool: pool) {
                ad.append(px, withPresentationTime: mapped); lastVideoPTS = mapped
                let seconds = CMTimeSubtract(mapped, fileStart).seconds
                DispatchQueue.main.async { self.elapsed = seconds }
            }
            return
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

    /// Центральный кусок 16:9 из высокого кадра.
    private func cropped(_ src: CVPixelBuffer, pool: CVPixelBufferPool) -> CVPixelBuffer? {
        let r = CameraMath.landscapeCrop(width: CVPixelBufferGetWidth(src), height: CVPixelBufferGetHeight(src))
        var out: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &out)
        guard let out else { return nil }
        let image = CIImage(cvPixelBuffer: src)
            .cropped(to: CGRect(x: r.x, y: r.y, width: r.w, height: r.h))
            .transformed(by: CGAffineTransform(translationX: -CGFloat(r.x), y: -CGFloat(r.y)))
        ciContext.render(image, to: out)
        return out
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
