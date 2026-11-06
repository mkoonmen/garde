import Foundation
import UIKit
import FoundationModels
import MLXLLM
import MLXLMCommon
import MLXHuggingFace
import MLXFoundationModels
import HuggingFace
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
    var usingLocal: Bool { brain == .local8B && localSupported && downloadState == .ready }

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
    func session(instructions: String) -> LanguageModelSession {
        if #available(iOS 27.0, *), usingLocal {
            let model = #huggingFaceLanguageModel(configuration: Self.modelConfig, capabilities: [.guidedGeneration])
            return LanguageModelSession(model: model, instructions: instructions)
        }
        return LanguageModelSession(instructions: instructions)
    }
}
