import AVFoundation
import ChatCore
import Foundation
import Observation
import Speech

/// Reads replies aloud.
@MainActor
@Observable
final class SpeechOutput {
    private(set) var speakingID: UUID?

    @ObservationIgnored private let synthesizer = AVSpeechSynthesizer()
    @ObservationIgnored private let delegate = SynthesizerDelegate()
    @ObservationIgnored private var onFinish: (() -> Void)?

    init() {
        synthesizer.delegate = delegate
        delegate.onDone = { @Sendable [weak self] in
            Task { @MainActor in self?.finished() }
        }
    }

    func speak(_ markdown: String, id: UUID, onFinish: (() -> Void)? = nil) {
        stop()
        let text = Markdown.speakableText(from: markdown)
        guard !text.isEmpty else {
            onFinish?()
            return
        }
        AudioSessionConfig.forPlayback()
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = Self.bestVoice()
        speakingID = id
        self.onFinish = onFinish
        synthesizer.speak(utterance)
    }

    func stop() {
        onFinish = nil
        speakingID = nil
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
    }

    private func finished() {
        guard speakingID != nil else { return }
        speakingID = nil
        let callback = onFinish
        onFinish = nil
        callback?()
    }

    /// The best installed voice for the user's language (premium or enhanced if downloaded).
    private static func bestVoice() -> AVSpeechSynthesisVoice? {
        let language = AVSpeechSynthesisVoice.currentLanguageCode()
        let voices = AVSpeechSynthesisVoice.speechVoices().filter { $0.language == language }
        return voices.first { $0.quality == .premium }
            ?? voices.first { $0.quality == .enhanced }
            ?? AVSpeechSynthesisVoice(language: language)
    }
}

private final class SynthesizerDelegate: NSObject, AVSpeechSynthesizerDelegate, @unchecked Sendable {
    var onDone: (@Sendable () -> Void)?

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        onDone?()
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        onDone?()
    }
}

/// Live dictation for voice mode. Uses on-device recognition when the device supports it,
/// so audio doesn't leave the device.
@MainActor
@Observable
final class SpeechInput {
    enum Status: Equatable {
        case idle
        case listening
        case unavailable(String)
    }

    private(set) var transcript = ""
    private(set) var level: Double = 0
    private(set) var status: Status = .idle

    @ObservationIgnored private let engine = AVAudioEngine()
    @ObservationIgnored private let recognizer = SFSpeechRecognizer()
    @ObservationIgnored private var request: SFSpeechAudioBufferRecognitionRequest?
    @ObservationIgnored private var task: SFSpeechRecognitionTask?

    func requestAccess() async -> Bool {
        let speech = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard speech == .authorized else {
            status = .unavailable("Speech recognition is turned off for this app. You can allow it in Settings.")
            return false
        }
        #if os(iOS)
        let mic = await AVAudioApplication.requestRecordPermission()
        #else
        let mic = await AVCaptureDevice.requestAccess(for: .audio)
        #endif
        guard mic else {
            status = .unavailable("Microphone access is turned off for this app. You can allow it in Settings.")
            return false
        }
        return true
    }

    func start() {
        stop()
        transcript = ""
        guard let recognizer, recognizer.isAvailable else {
            status = .unavailable("Speech recognition isn't available right now.")
            return
        }
        AudioSessionConfig.forRecording()

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }
        self.request = request

        let input = engine.inputNode
        input.removeTap(onBus: 0)
        input.installTap(
            onBus: 0,
            bufferSize: 1024,
            format: input.outputFormat(forBus: 0),
            block: Self.tapBlock(request: request) { @Sendable [weak self] rms in
                Task { @MainActor in self?.updateLevel(rms) }
            }
        )
        engine.prepare()
        do {
            try engine.start()
        } catch {
            status = .unavailable("Couldn't start the microphone: \(error.localizedDescription)")
            return
        }
        task = recognizer.recognitionTask(with: request, resultHandler: Self.resultHandler { @Sendable [weak self] text, isFinal in
            Task { @MainActor in self?.handle(text: text, isFinal: isFinal) }
        })
        status = .listening
    }

    func stop() {
        if engine.isRunning {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
        }
        request?.endAudio()
        request = nil
        task?.cancel()
        task = nil
        level = 0
        if status == .listening { status = .idle }
    }

    func clear() {
        transcript = ""
    }

    private func updateLevel(_ rms: Float) {
        let target = min(1, Double(rms) * 9)
        level = level * 0.6 + target * 0.4
    }

    private func handle(text: String?, isFinal: Bool) {
        guard status == .listening else { return }
        if let text { transcript = text }
        if isFinal { stop() }
    }

    // Built outside the main actor: the audio engine and recognizer call these on their own threads.
    nonisolated private static func tapBlock(
        request: SFSpeechAudioBufferRecognitionRequest,
        level: @escaping @Sendable (Float) -> Void
    ) -> AVAudioNodeTapBlock {
        { buffer, _ in
            request.append(buffer)
            guard let samples = buffer.floatChannelData?[0] else { return }
            let count = Int(buffer.frameLength)
            guard count > 0 else { return }
            var sum: Float = 0
            for i in 0..<count { sum += samples[i] * samples[i] }
            level((sum / Float(count)).squareRoot())
        }
    }

    nonisolated private static func resultHandler(
        _ forward: @escaping @Sendable (String?, Bool) -> Void
    ) -> (SFSpeechRecognitionResult?, Error?) -> Void {
        { result, error in
            forward(result?.bestTranscription.formattedString, (result?.isFinal ?? false) || error != nil)
        }
    }
}

enum AudioSessionConfig {
    static func forRecording() {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .duckOthers])
        try? session.setActive(true, options: .notifyOthersOnDeactivation)
        #endif
    }

    static func forPlayback() {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        if session.category != .playAndRecord {
            try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        }
        try? session.setActive(true, options: .notifyOthersOnDeactivation)
        #endif
    }
}
