import Foundation
import os
import UIKit
import FoundationModels
import MLXLLM
import MLXLMCommon
import MLXHuggingFace
import MLXFoundationModels
import HuggingFace
import MLX
import Tokenizers

/// Which brain the chef uses. Both run entirely on the iPhone.
///  • apple: Apple's built-in ~3B model. Instant, no download.
///  • local8B: Qwen3 8B (4-bit, ~4.7 GB) run with MLX. Better recipes and longer chats; one-time download.
/// Both plug into the same LanguageModelSession API, so @Generable structured output works with either.
enum ChefBrain: String, CaseIterable, Identifiable {
    case apple, local8B
    var id: String { rawValue }
    var label: String { self == .apple ? "Apple (built in)" : "Qwen3 8B (downloaded)" }
    var detail: String {
        self == .apple ? "Fast, no download. Good for everyday ideas."
                       : "About 4.7 GB, downloaded once over Wi-Fi. Noticeably better recipes and conversation. Uses more battery."
    }
}

/// MLX reports errors on worker threads while sessions are created on the main actor.
struct LaunchModelFaults: Sendable {
    private enum Fault: Sendable { case timedOut, gpu(String) }
    private let fault = OSAllocatedUnfairLock<Fault?>(initialState: nil)

    var message: String? {
        fault.withLock {
            switch $0 {
            case nil: return nil
            case .timedOut: return "timed out"
            case .gpu(let message): return message
            }
        }
    }

    /// A failed Metal command can trigger several callbacks. Count the affected launch once.
    func recordGPU(_ message: String) -> Bool {
        fault.withLock { current in
            if case .gpu = current { return false }
            current = .gpu(message)
            return true
        }
    }

    func recordTimeout() {
        fault.withLock { if $0 == nil { $0 = .timedOut } }
    }
}

@MainActor
@Observable
final class ChefEngine {
    static let shared = ChefEngine()

    enum DownloadState: Equatable { case notDownloaded, downloading(Double), ready, failed(String) }

    static let modelConfig = ModelConfiguration(id: "mlx-community/Qwen3-8B-4bit")

    var brain = ChefBrain(rawValue: UserDefaults.standard.string(forKey: "chef.brain") ?? "") ?? .apple {
        didSet { UserDefaults.standard.set(brain.rawValue, forKey: "chef.brain") }
    }
    var autoSwitchedNote = UserDefaults.standard.string(forKey: "chef.autoSwitched") {
        didSet { UserDefaults.standard.set(autoSwitchedNote, forKey: "chef.autoSwitched") }
    }
    var downloadState: DownloadState = UserDefaults.standard.bool(forKey: "chef.local8BReady") ? .ready : .notDownloaded

    /// The 8B model can only drive LanguageModelSession on iOS 27+.
    var localSupported: Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        if #available(iOS 27.0, *) { return true }
        return false
        #endif
    }

    /// True when the selected brain is usable right now.
    /// The phone's GPU can't be used while Garde is in the background, and after a GPU fault this launch we stay on Apple's model.
    var usingLocal: Bool {
        brain == .local8B && localSupported && downloadState == .ready && Self.mlxFault == nil
            && UIApplication.shared.applicationState != .background
    }

    /// Last GPU error from the downloaded model this launch (nil = fine).
    nonisolated static let launchFaults = LaunchModelFaults()
    nonisolated static var mlxFault: String? { launchFaults.message }
    /// After two launches with a GPU error we switch back to Apple's model.
    static var faultCount: Int {
        get { UserDefaults.standard.integer(forKey: "chef.mlxFaults") }
        set { UserDefaults.standard.set(newValue, forKey: "chef.mlxFaults") }
    }
    /// By default MLX kills the whole app on any GPU error (that was the crash in 2.9.5).
    /// This turns those errors into "fall back to Apple's model" instead, and keeps MLX's memory cache small.
    nonisolated static func installSafety() {
        #if !targetEnvironment(simulator)
        setErrorHandler({ message, _ in
            let text = message.map { String(cString: $0) } ?? "GPU error"
            if ChefEngine.launchFaults.recordGPU(text) {
                Task { @MainActor in ChefEngine.recordFault(text) }
            }
        })
        #endif
    }
    /// Only touch MLX's GPU memory settings right before the downloaded model runs (never at launch / in the simulator).
    private static var memoryTuned = false
    private static func tuneMemory() {
        guard !memoryTuned else { return }
        memoryTuned = true
        Memory.cacheLimit = 256 * 1024 * 1024
    }

    private static func recordFault(_ text: String) {
        faultCount += 1
        UserDefaults.standard.set(text, forKey: "chef.lastFault")
        if faultCount >= 2 {
            shared.brain = .apple
            shared.autoSwitchedNote = "Qwen hit a phone GPU error twice, so Garde switched back to Apple's model. You can switch again any time."
            faultCount = 0
        }
    }

    /// Bytes written so far and a stall note, shown under the progress bar.
    var downloadedBytes: Int64 = 0
    var stalled = false
    var totalDownloadBytes: Int64 = 0
    private var downloadTask: Task<Void, Never>?

    /// Starts the download in a task the engine owns, so leaving Settings doesn't cancel it.
    func startDownload() {
        guard downloadTask == nil else { return }
        downloadTask = Task { await downloadLocalModel(); downloadTask = nil }
    }

    /// Fetch the model files without allocating GPU memory. A session loads them when needed.
    private func downloadLocalModel() async {
        guard localSupported else { downloadState = .failed("Needs an iPhone running iOS 27 or later."); return }
        downloadState = .downloading(0)
        downloadedBytes = 0
        totalDownloadBytes = 0
        stalled = false
        let previousIdleSetting = UIApplication.shared.isIdleTimerDisabled
        UIApplication.shared.isIdleTimerDisabled = true
        var bg: UIBackgroundTaskIdentifier = .invalid
        func endBackgroundTime() {
            guard bg != .invalid else { return }
            UIApplication.shared.endBackgroundTask(bg)
            bg = .invalid
        }
        bg = UIApplication.shared.beginBackgroundTask(withName: "model-download") { [weak self] in
            self?.downloadTask?.cancel()
            endBackgroundTime()
        }
        let watcher = Task { @MainActor in
            var lastBytes: Int64 = 0
            var lastChange = ContinuousClock.now
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(2)) } catch { return }
                if downloadedBytes != lastBytes {
                    lastBytes = downloadedBytes
                    lastChange = .now
                }
                stalled = .now - lastChange >= .seconds(60)
            }
        }
        defer {
            watcher.cancel()
            UIApplication.shared.isIdleTimerDisabled = previousIdleSetting
            endBackgroundTime()
        }
        do {
            _ = try await MLXLMCommon.resolve(configuration: Self.modelConfig, from: #hubDownloader(),
                                              useLatest: false) { progress in
                let total = progress.totalUnitCount
                // The cached-snapshot fast path sends a single synthetic 1/1.
                guard total > 1 else { return }
                let fraction = min(1, max(0, progress.fractionCompleted))
                let bytes = Int64((fraction * Double(total)).rounded())
                Task { @MainActor in
                    guard case .downloading(let previous) = self.downloadState, fraction >= previous else { return }
                    self.downloadedBytes = bytes
                    self.totalDownloadBytes = total
                    self.downloadState = .downloading(fraction)
                }
            }
            UserDefaults.standard.set(true, forKey: "chef.local8BReady")
            downloadState = .ready
        } catch {
            downloadState = .failed("Download stopped: \(error.localizedDescription) Tap Try again; it picks up where it left off.")
        }
    }

    /// A session on whichever brain is selected (falls back to Apple's model).
    /// `fast: true` always uses Apple's model (scanning, where speed matters more than prose).
    func session(instructions: String, fast: Bool = false) -> LanguageModelSession {
        if #available(iOS 27.0, *), usingLocal, !fast {
            Self.tuneMemory()
            let model = #huggingFaceLanguageModel(configuration: Self.modelConfig, capabilities: [.guidedGeneration])
            return LanguageModelSession(model: model, instructions: instructions)
        }
        return LanguageModelSession(instructions: instructions)
    }
}


struct AITimeoutError: LocalizedError {
    var errorDescription: String? { "The chef took too long. Try again." }
}

/// Runs a call and gives up after `seconds`, so a stuck model can never leave a spinner going forever.
enum AITimeout {
    static func run<T: Sendable>(seconds: Double, onTimeout: @Sendable () -> Void = { ChefEngine.launchFaults.recordTimeout() },
                                 _ op: @escaping @Sendable () async throws -> T) async throws -> T {
        try Task.checkCancellation()
        // Finishing the stream wakes the caller even if the model ignores cancellation.
        let (stream, result) = AsyncThrowingStream<T, Error>.makeStream()
        let work = Task {
            do {
                result.yield(try await op())
                result.finish()
            } catch { result.finish(throwing: error) }
        }
        let timer = Task {
            do { try await Task.sleep(for: .seconds(seconds)) } catch { return }
            result.finish(throwing: AITimeoutError())
        }
        defer { timer.cancel(); work.cancel() }
        var iterator = stream.makeAsyncIterator()
        do {
            guard let value = try await iterator.next() else { throw CancellationError() }
            return value
        } catch is AITimeoutError {
            onTimeout()
            throw AITimeoutError()
        }
    }
}

extension LanguageModelSession {
    func reply(to prompt: String, limit: Double = 90) async throws -> String {
        try await AITimeout.run(seconds: limit) { try await self.respond(to: prompt).content }
    }

    /// `respond(to:generating:)` with a time limit.
    func reply<T: Generable & Sendable>(to prompt: String, generating type: T.Type, limit: Double = 90) async throws -> T {
        try await AITimeout.run(seconds: limit) { try await self.respond(to: prompt, generating: type).content }
    }
}
