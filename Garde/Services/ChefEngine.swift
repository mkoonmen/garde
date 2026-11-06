import Foundation
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

@MainActor
@Observable
final class ChefEngine {
    static let shared = ChefEngine()

    enum DownloadState: Equatable { case notDownloaded, downloading(Double), ready, failed(String) }

    static let modelConfig = ModelConfiguration(id: "mlx-community/Qwen3-8B-4bit")

    var brain: ChefBrain {
        get { ChefBrain(rawValue: UserDefaults.standard.string(forKey: "chef.brain") ?? "") ?? .apple }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "chef.brain") }
    }
    var downloadState: DownloadState = UserDefaults.standard.bool(forKey: "chef.local8BReady") ? .ready : .notDownloaded

    /// The 8B model can only drive LanguageModelSession on iOS 27+.
    var localSupported: Bool {
        if #available(iOS 27.0, *) { return true }
        return false
    }

    /// True when the selected brain is usable right now.
    /// The phone's GPU can't be used while Garde is in the background, and after a GPU fault this launch we stay on Apple's model.
    var usingLocal: Bool {
        brain == .local8B && localSupported && downloadState == .ready && Self.mlxFault == nil
            && UIApplication.shared.applicationState != .background
    }

    /// Last GPU error from the downloaded model this launch (nil = fine).
    nonisolated(unsafe) static var mlxFault: String?
    /// How many launches in a row hit a GPU error; after 2 we switch back to Apple's model.
    static var faultCount: Int {
        get { UserDefaults.standard.integer(forKey: "chef.mlxFaults") }
        set { UserDefaults.standard.set(newValue, forKey: "chef.mlxFaults") }
    }
    var autoSwitchedNote: String? { UserDefaults.standard.string(forKey: "chef.autoSwitched") }

    /// By default MLX kills the whole app on any GPU error (that was the crash in 2.9.5).
    /// This turns those errors into "fall back to Apple's model" instead, and keeps MLX's memory cache small.
    static func installSafety() {
        #if targetEnvironment(simulator)
        return
        #endif
        setErrorHandler({ message, _ in
            let text = message.map { String(cString: $0) } ?? "GPU error"
            ChefEngine.mlxFault = text
            DispatchQueue.main.async { ChefEngine.recordFault(text) }
        })
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
            UserDefaults.standard.set(ChefBrain.apple.rawValue, forKey: "chef.brain")
            UserDefaults.standard.set("Qwen hit a phone GPU error twice, so Garde switched back to Apple's model. You can switch again any time.", forKey: "chef.autoSwitched")
            faultCount = 0
        }
    }

    /// Bytes written so far and a stall note, shown under the progress bar.
    var downloadedBytes: Int64 = 0
    var stalled = false
    static let modelBytes: Int64 = 4_700_000_000
    private var downloadTask: Task<Void, Never>?

    /// Starts the download in a task the engine owns, so leaving Settings doesn't cancel it.
    func startDownload() {
        guard downloadTask == nil else { return }
        downloadTask = Task { await downloadLocalModel(); downloadTask = nil }
    }

    /// Downloads (once) and warms up the 8B model.
    /// The library only reports progress per finished file, and the weights are one ~4.5 GB file,
    /// so it sat at 0% for ages. We also watch how many bytes have landed on disk.
    func downloadLocalModel() async {
        guard localSupported else { downloadState = .failed("Needs iOS 27 or later."); return }
        downloadState = .downloading(0); stalled = false
        UIApplication.shared.isIdleTimerDisabled = true   // screen lock pauses the download
        let bg = UIApplication.shared.beginBackgroundTask(withName: "model-download")
        let base = Self.diskBytes()
        let watcher = Task { @MainActor in
            var last: Int64 = 0, quiet = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                let now = max(0, Self.diskBytes() - base)
                downloadedBytes = now
                quiet = now > last ? 0 : quiet + 1
                stalled = quiet >= 30   // a minute with nothing new
                last = now
                if case .downloading(let f) = downloadState {
                    let est = min(0.99, Double(now) / Double(Self.modelBytes))
                    if est > f { downloadState = .downloading(est) }
                }
            }
        }
        defer {
            watcher.cancel()
            UIApplication.shared.isIdleTimerDisabled = false
            UIApplication.shared.endBackgroundTask(bg)
        }
        do {
            _ = try await #huggingFaceLoadModelContainer(configuration: Self.modelConfig) { progress in
                Task { @MainActor in
                    if case .downloading(let f) = self.downloadState, progress.fractionCompleted > f {
                        self.downloadState = .downloading(progress.fractionCompleted)
                    }
                }
            }
            UserDefaults.standard.set(true, forKey: "chef.local8BReady")
            downloadState = .ready
        } catch {
            downloadState = .failed("Download stopped: \(error.localizedDescription) Tap Try again; it picks up where it left off.")
        }
    }

    /// Size of the places the downloader writes to (caches, temp, documents).
    nonisolated static func diskBytes() -> Int64 {
        let fm = FileManager.default
        var dirs = [fm.temporaryDirectory]
        dirs += fm.urls(for: .cachesDirectory, in: .userDomainMask)
        dirs += fm.urls(for: .documentDirectory, in: .userDomainMask)
        dirs += fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        var total: Int64 = 0
        for d in dirs {
            guard let e = fm.enumerator(at: d, includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .fileSizeKey]) else { continue }
            for case let u as URL in e {
                let v = try? u.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileSizeKey])
                total += Int64(v?.totalFileAllocatedSize ?? v?.fileSize ?? 0)
            }
        }
        return total
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
    private final class Once: @unchecked Sendable {
        private let lock = NSLock(); private var done = false
        func claim() -> Bool { lock.withLock { if done { return false }; done = true; return true } }
    }
    static func run<T>(seconds: Double, _ op: @escaping () async throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<T, Error>) in
            let once = Once()
            let work = Task {
                do { let v = try await op(); if once.claim() { cont.resume(returning: v) } }
                catch { if once.claim() { cont.resume(throwing: error) } }
            }
            Task {
                try? await Task.sleep(for: .seconds(seconds))
                if once.claim() {
                    work.cancel()
                    // A stuck downloaded model: use Apple's model for the rest of this launch.
                    await MainActor.run { if ChefEngine.shared.usingLocal { ChefEngine.mlxFault = "timed out" } }
                    cont.resume(throwing: AITimeoutError())
                }
            }
        }
    }
}

extension LanguageModelSession {
    /// `respond(to:generating:)` with a time limit.
    func reply<T: Generable>(to prompt: String, generating type: T.Type, limit: Double = 90) async throws -> T {
        try await AITimeout.run(seconds: limit) { try await self.respond(to: prompt, generating: type).content }
    }
}
