import SwiftUI
import PhotosUI

/// Wraps the system camera.
struct CameraPicker: UIViewControllerRepresentable {
    var onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ vc: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let img = info[.originalImage] as? UIImage { parent.onImage(img) }
            parent.dismiss()
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    }
}

/// Small photo attach control for a single item.
struct PhotoField: View {
    @Binding var data: Data?
    @State private var showCamera = false
    @State private var pick: PhotosPickerItem?

    var body: some View {
        if let data, let img = UIImage(data: data) {
            Image(uiImage: img).resizable().scaledToFit().frame(maxHeight: 220).clipShape(.rect(cornerRadius: 10))
            Button("Remove photo", role: .destructive) { self.data = nil }
        }
        HStack {
            Button("Take photo", systemImage: "camera") { showCamera = true }
            Spacer()
            PhotosPicker(selection: $pick, matching: .images) { Label("Library", systemImage: "photo") }
        }
        .buttonStyle(.borderless)
        .fullScreenCover(isPresented: $showCamera) { CameraPicker { data = $0.storageJPEG(maxDimension: 900) }.ignoresSafeArea() }
        .onChange(of: pick) { _, new in
            Task {
                if let raw = try? await new?.loadTransferable(type: Data.self), let img = UIImage(data: raw) {
                    data = img.storageJPEG(maxDimension: 900)
                }
            }
        }
    }
}
