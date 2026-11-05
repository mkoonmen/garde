import UIKit
import SwiftUI
import UniformTypeIdentifiers

/// "Share → Garde" from Safari, TikTok, Instagram, YouTube, Photos, Notes…
/// Saves the link / text / photo to Garde's inbox; Garde turns it into a recipe the next time it opens.
final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        let host = UIHostingController(rootView: SharedConfirmation(state: .saving))
        addChild(host); view.addSubview(host.view)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        host.didMove(toParent: self)

        Task {
            let saved = await collect()
            host.rootView = SharedConfirmation(state: saved ? .saved : .nothing)
            try? await Task.sleep(for: .seconds(saved ? 1.2 : 2))
            extensionContext?.completeRequest(returningItems: nil)
        }
    }

    private func collect() async -> Bool {
        let providers = (extensionContext?.inputItems as? [NSExtensionItem] ?? []).flatMap { $0.attachments ?? [] }
        var url: String?, text: String?, image: Data?
        for p in providers {
            if url == nil, p.hasItemConformingToTypeIdentifier(UTType.url.identifier),
               let u = try? await p.loadItem(forTypeIdentifier: UTType.url.identifier) as? URL, !u.isFileURL {
                url = u.absoluteString
            }
            if text == nil, p.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
               let t = try? await p.loadItem(forTypeIdentifier: UTType.plainText.identifier) as? String {
                text = t
            }
            if image == nil, p.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                let item = try? await p.loadItem(forTypeIdentifier: UTType.image.identifier)
                if let u = item as? URL { image = try? Data(contentsOf: u) }
                else if let d = item as? Data { image = d }
                else if let img = item as? UIImage { image = img.jpegData(compressionQuality: 0.8) }
            }
        }
        // A pasted caption often contains the link too.
        if url == nil, let t = text, let found = t.firstMatch(of: /https?:\/\/\S+/) { url = String(found.0) }
        // Re-encode photos as JPEG (HEIC/PNG from Photos) and keep them small.
        if let raw = image, let img = UIImage(data: raw) { image = img.jpegData(compressionQuality: 0.8) }
        guard url != nil || text != nil || image != nil else { return false }
        RecipeInbox.add(url: url, text: text, imageData: image)
        return true
    }
}

struct SharedConfirmation: View {
    enum State { case saving, saved, nothing }
    let state: State
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: state == .nothing ? "questionmark.circle" : "fork.knife.circle.fill")
                .font(.system(size: 54)).foregroundStyle(Color(red: 21 / 255, green: 34 / 255, blue: 79 / 255))
            Text(state == .saving ? "Sending to Garde…" : state == .saved ? "Saved to Garde" : "Nothing Garde can use here")
                .font(.title3.weight(.semibold)).fontDesign(.serif)
            if state == .saved { Text("Open Garde to see the recipe.").foregroundStyle(.secondary) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 242 / 255, green: 234 / 255, blue: 216 / 255))
    }
}
