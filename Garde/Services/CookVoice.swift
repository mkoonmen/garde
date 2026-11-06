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
    var problem: String?           // shown in cook mode when listening can't start
    var onCommand: ((Command) -> Void)?

    enum Command { case next, back, repeatStep, startTimer, timeLeft, stop }

    private let synth = AVSpeechSynthesizer()
    private let engine = AVAudioEngine()
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var lastCommandAt = Date.distantPast
    private var generation = 0   // ignores callbacks from recognition tasks we've already replaced
    private var restarts: [Date] = []
    private var quietUntil = Date.distantPast   // ignore what the mic hears while (and just after) Garde reads aloud
    private let speechDelegate = SpeechDelegate()

    private final class SpeechDelegate: NSObject, AVSpeechSynthesizerDelegate {
        var onFinish: (() -> Void)?
        func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish u: AVSpeechUtterance) { onFinish?() }
        func speechSynthesizer(_ s: AVSpeechSynthesizer, didCancel u: AVSpeechUtterance) { onFinish?() }
    }

    init() {
        synth.delegate = speechDelegate
        speechDelegate.onFinish = { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.quietUntil = .now.addingTimeInterval(0.8)
                // Start a fresh transcript so words heard while Garde was talking can't fire a command late.
                if self.isListening, let r = self.recognizer {
                    self.engine.stop()
                    do { try self.beginRecognition(r) } catch { self.stop(); self.problem = "Listening stopped. Tap Voice to start again." }
                }
            }
        }
    }

    func speak(_ text: String) {
        synth.stopSpeaking(at: .immediate)
        let u = AVSpeechUtterance(string: text)
        u.rate = 0.5
        quietUntil = .distantFuture   // until the delegate says it finished
        synth.speak(u)
    }

    func start() async {
        let speechOK = await withCheckedContinuation { c in SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0 == .authorized) } }
        let micOK = await AVAudioApplication.requestRecordPermission()
        problem = nil
        guard speechOK, micOK else { problem = "Microphone or speech recognition access is off for Garde."; return }
        guard let recognizer, recognizer.isAvailable else { problem = "Speech recognition isn't available right now."; return }
        do {
            let session = AVAudioSession.sharedInstance()
            // voiceChat turns on echo cancellation so Garde doesn't hear itself reading steps aloud.
            try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .duckOthers])
            try session.setActive(true)
            try beginRecognition(recognizer)
            isListening = true
            restarts = []
        } catch { stop(); problem = "Couldn't start listening. Try again." }
    }

    private func beginRecognition(_ recognizer: SFSpeechRecognizer) throws {
        generation += 1
        let gen = generation
        request?.endAudio()
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
                guard let self, gen == self.generation else { return }
                if let text = result?.bestTranscription.formattedString.lowercased() {
                    self.heard = text
                    self.handle(text)
                }
                // Recognition tasks time out after ~1 min; restart quietly to keep listening.
                if error != nil || result?.isFinal == true, self.isListening {
                    self.restart(recognizer)
                }
            }
        }
    }

    /// Restart after a timeout or interruption, but give up (instead of looping and draining battery) after 3 fails in 10 s.
    private func restart(_ recognizer: SFSpeechRecognizer) {
        restarts = restarts.filter { $0 > .now.addingTimeInterval(-10) } + [.now]
        engine.stop()
        guard restarts.count <= 3 else { stop(); problem = "Listening stopped. Tap Voice to start again."; return }
        do { try beginRecognition(recognizer) } catch { stop(); problem = "Listening stopped. Tap Voice to start again." }
    }

    private func handle(_ text: String) {
        guard Date.now.timeIntervalSince(lastCommandAt) > 1.5, !synth.isSpeaking, Date.now > quietUntil else { return }
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
        if let recognizer {
            do { try beginRecognition(recognizer) } catch { stop(); problem = "Listening stopped. Tap Voice to start again." }
        }
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

    /// Finds the first duration in a step ("simmer 10 minutes", "rest 5-7 min", "bake 1 1/2 hours") in seconds.
    /// Ranges use the longer end.
    nonisolated static func duration(in step: String) -> Int? {
        let s = step.lowercased()
        if let m = s.firstMatch(of: /(\d+)\s*(?:-|to)\s*(\d+)\s*(hours?|hrs?|minutes?|mins?|seconds?|secs?)\b/),
           let hi = Int(m.2) { return hi * unit(String(m.3)) }
        if let m = s.firstMatch(of: /(\d+)\s+(\d)\/(\d)\s*(hours?|hrs?|minutes?|mins?|seconds?|secs?)\b/),
           let whole = Double(m.1), let num = Double(m.2), let den = Double(m.3), den > 0 {
            return Int((whole + num / den) * Double(unit(String(m.4))))
        }
        if let m = s.firstMatch(of: /(\d+(?:\.\d+)?)\s*(hours?|hrs?|minutes?|mins?|seconds?|secs?)\b/), let n = Double(m.1) {
            return Int(n * Double(unit(String(m.2))))
        }
        return nil
    }
    nonisolated private static func unit(_ u: String) -> Int { u.hasPrefix("h") ? 3600 : u.hasPrefix("s") ? 1 : 60 }
}
