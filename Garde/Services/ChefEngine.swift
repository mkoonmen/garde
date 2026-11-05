import Foundation
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

    /// Downloads (once) and warms up the 8B model.
    func downloadLocalModel() async {
        guard localSupported else { downloadState = .failed("Needs iOS 27 or later."); return }
        downloadState = .downloading(0)
        do {
            _ = try await #huggingFaceLoadModelContainer(configuration: Self.modelConfig) { progress in
                Task { @MainActor in self.downloadState = .downloading(progress.fractionCompleted) }
            }
            UserDefaults.standard.set(true, forKey: "chef.local8BReady")
            downloadState = .ready
        } catch {
            downloadState = .failed(error.localizedDescription)
        }
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
