import Foundation
import Speech
import AVFoundation

/// Hands-free cooking: reads steps aloud and listens for "next", "back", "repeat",
/// "start timer", "how long left". Speech recognition runs on-device.
@MainActor
@Observable
final class CookVoice {
    var isListening = false
    var heard = ""
    var onCommand: ((Command) -> Void)?

    enum Command { case next, back, repeatStep, startTimer, timeLeft, stop }

    private let synth = AVSpeechSynthesizer()
    private let engine = AVAudioEngine()
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var lastCommandAt = Date.distantPast

    func speak(_ text: String) {
        synth.stopSpeaking(at: .immediate)
        let u = AVSpeechUtterance(string: text)
        u.rate = 0.5
        synth.speak(u)
    }

    func start() async {
        let speechOK = await withCheckedContinuation { c in SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0 == .authorized) } }
        let micOK = await AVAudioApplication.requestRecordPermission()
        guard speechOK, micOK, let recognizer, recognizer.isAvailable else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .duckOthers])
            try session.setActive(true)
            try beginRecognition(recognizer)
            isListening = true
        } catch { stop() }
    }

    private func beginRecognition(_ recognizer: SFSpeechRecognizer) throws {
        task?.cancel()
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition { req.requiresOnDeviceRecognition = true }
        request = req
        let input = engine.inputNode
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { [weak req] buf, _ in req?.append(buf) }
        engine.prepare()
        try engine.start()
        task = recognizer.recognitionTask(with: req) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }
                if let text = result?.bestTranscription.formattedString.lowercased() {
                    self.heard = text
                    self.handle(text)
                }
                // Recognition tasks time out after ~1 min; restart quietly to keep listening.
                if error != nil || result?.isFinal == true, self.isListening {
                    self.engine.stop()
                    try? self.beginRecognition(recognizer)
                }
            }
        }
    }

    private func handle(_ text: String) {
        guard Date.now.timeIntervalSince(lastCommandAt) > 1.5 else { return }
        let last = text.split(separator: " ").suffix(4).joined(separator: " ")
        let cmd: Command? =
            last.contains("next") ? .next :
            last.contains("back") || last.contains("previous") ? .back :
            last.contains("repeat") || last.contains("again") ? .repeatStep :
            last.contains("start timer") || last.contains("start the timer") ? .startTimer :
            last.contains("how long") || last.contains("time left") ? .timeLeft :
            last.contains("stop listening") ? .stop : nil
        guard let cmd else { return }
        lastCommandAt = .now
        // Reset so the same word isn't matched twice.
        engine.stop()
        if let recognizer { try? beginRecognition(recognizer) }
        onCommand?(cmd)
    }

    func stop() {
        isListening = false
        task?.cancel(); task = nil
        request?.endAudio(); request = nil
        if engine.isRunning { engine.stop() }
        engine.inputNode.removeTap(onBus: 0)
        synth.stopSpeaking(at: .immediate)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// Finds the first duration in a step ("simmer 10 minutes", "bake for 1 hour") in seconds.
    static func duration(in step: String) -> Int? {
        let s = step.lowercased()
        if let m = s.firstMatch(of: /(\d+)\s*(?:-|to)\s*(\d+)\s*(hours?|hrs?|minutes?|mins?|seconds?|secs?)/),
           let hi = Int(m.2) { return hi * unit(String(m.3)) }
        if let m = s.firstMatch(of: /(\d+)\s*(hours?|hrs?|minutes?|mins?|seconds?|secs?)/), let n = Int(m.1) { return n * unit(String(m.2)) }
        return nil
    }
    private static func unit(_ u: String) -> Int { u.hasPrefix("h") ? 3600 : u.hasPrefix("s") ? 1 : 60 }
}
