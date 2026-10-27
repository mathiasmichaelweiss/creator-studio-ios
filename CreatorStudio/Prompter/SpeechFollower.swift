import AVFoundation
import Speech
import UIKit

/// Суфлёр по голосу: слушает микрофон записи, распознаёт речь на телефоне
/// и сообщает, до какого слова сценария ты дошёл.
@MainActor
final class SpeechFollower: ObservableObject {
    enum Status: Equatable {
        case off, listening, denied, unavailable
        var text: String {
            switch self {
            case .off: ""
            case .listening: "Слушаю"
            case .denied: "Нет доступа к распознаванию речи. Einstellungen → Apps → Студия → Spracherkennung."
            case .unavailable: "Распознавание речи сейчас недоступно. Переключись на «По скорости»."
            }
        }
    }

    @Published private(set) var status: Status = .off
    /// Позиция (UTF-16) последнего сказанного слова в тексте сценария.
    @Published private(set) var location: Int?

    private var aligner = ScriptAligner(text: "")
    private var alignedText = ""
    private var task: SFSpeechRecognitionTask?
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "ru-RU"))
    /// Запрос, в который пишет очередь камеры. Доступ только под замком.
    private let box = RequestBox()
    private var shouldListen = false
    /// Номер текущего запроса: ответы от старых (отменённых) запросов игнорируются.
    private var generation = 0

    static func requestAccess() async -> Bool {
        await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { cont.resume(returning: $0 == .authorized) }
        }
    }

    /// Новый текст сценария: позиция сбрасывается в начало.
    func load(script: String) {
        guard script != alignedText else { return }
        alignedText = script
        aligner = ScriptAligner(text: script)
        location = nil
    }

    func resetPosition() {
        aligner.reset()
        location = nil
    }

    func start() async {
        guard await Self.requestAccess() else { status = .denied; return }
        guard let recognizer, recognizer.isAvailable else { status = .unavailable; return }
        shouldListen = true
        status = .listening
        begin(with: recognizer)
    }

    func stop() {
        shouldListen = false
        generation += 1
        box.set(nil)?.endAudio()
        task?.cancel()
        task = nil
        if status == .listening { status = .off }
    }

    /// Звук с микрофона записи. Вызывается с очереди камеры.
    nonisolated func append(_ buffer: CMSampleBuffer) {
        box.get()?.appendAudioSampleBuffer(buffer)
    }

    private func begin(with recognizer: SFSpeechRecognizer) {
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        req.taskHint = .dictation
        if recognizer.supportsOnDeviceRecognition { req.requiresOnDeviceRecognition = true }
        // Подсказки распознаванию: длинные слова из сценария (лимит Apple 100).
        req.contextualStrings = Array(Set(aligner.words.map(\.norm).filter { $0.count >= 6 })).prefix(100).map { $0 }
        box.set(req)
        generation += 1
        let gen = generation

        task = recognizer.recognitionTask(with: req) { [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let done = (result?.isFinal ?? false) || error != nil
            Task { @MainActor in self?.handle(text: text, done: done, generation: gen) }
        }
    }

    private func handle(text: String?, done: Bool, generation gen: Int) {
        guard gen == generation else { return }
        if let text, let index = aligner.consume(transcript: text) {
            location = aligner.words[index].location
        }
        // Распознавание само заканчивается после паузы или лимита: запускаем заново с того же места.
        if done, shouldListen, let recognizer {
            task = nil
            begin(with: recognizer)
        }
    }
}

/// Потокобезопасная ссылка на текущий запрос распознавания.
private final class RequestBox: @unchecked Sendable {
    private let lock = NSLock()
    private var request: SFSpeechAudioBufferRecognitionRequest?

    func get() -> SFSpeechAudioBufferRecognitionRequest? {
        lock.lock(); defer { lock.unlock() }
        return request
    }

    /// Ставит новый запрос и возвращает прежний.
    @discardableResult
    func set(_ new: SFSpeechAudioBufferRecognitionRequest?) -> SFSpeechAudioBufferRecognitionRequest? {
        lock.lock(); defer { lock.unlock() }
        let old = request
        request = new
        return old
    }
}

/// Где на экране строка с нужным символом: та же вёрстка, что у текста суфлёра.
enum PrompterLayout {
    static func lineTop(of location: Int, in text: String, fontSize: CGFloat, lineSpacing: CGFloat, width: CGFloat) -> CGFloat {
        guard width > 0, !text.isEmpty else { return 0 }
        let font = UIFont(name: Typo.postScriptName(.semibold), size: fontSize) ?? .systemFont(ofSize: fontSize, weight: .semibold)
        let style = NSMutableParagraphStyle()
        style.lineSpacing = lineSpacing
        let storage = NSTextStorage(string: text, attributes: [.font: font, .paragraphStyle: style])
        let manager = NSLayoutManager()
        let container = NSTextContainer(size: CGSize(width: width, height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        manager.addTextContainer(container)
        storage.addLayoutManager(manager)

        let length = (text as NSString).length
        let charIndex = min(max(0, location), max(0, length - 1))
        let glyph = manager.glyphIndexForCharacter(at: charIndex)
        return manager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil).minY
    }
}
