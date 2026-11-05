import SwiftUI
import SwiftData
import VisionKit
import AVFoundation

/// Point the camera at groceries: barcodes beep in one after another (looked up in Open Food Facts),
/// and tapping a printed date assigns it to the last item.
struct LiveScanView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query private var profiles: [KitchenProfile]

    struct Captured: Identifiable {
        let id = UUID()
        var code: String
        var name: String
        var category: FoodCategory
        var expiration: Date?
        var allergyWarning: [String] = []
        var resolved = false
    }

    @State private var captured: [Captured] = []
    @State private var seen: Set<String> = []
    @State private var dateHint = ""
    @State private var cameraAllowed: Bool?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if cameraAllowed == nil {
                    ProgressView().frame(maxHeight: .infinity)
                } else if cameraAllowed == true && DataScannerViewController.isSupported && DataScannerViewController.isAvailable {
                    ScannerRepresentable(onBarcode: handleBarcode, onText: handleText)
                        .frame(maxHeight: .infinity)
                        .overlay(alignment: .bottom) {
                            Text(dateHint.isEmpty ? "Scan barcodes. Tap a printed date to attach it to the last item." : dateHint)
                                .font(.footnote.weight(.medium)).padding(8).background(.ultraThinMaterial, in: .capsule).padding()
                        }
                } else {
                    ContentUnavailableView("Live scanning isn't available", systemImage: "camera.metering.unknown",
                                           description: Text("Allow camera access in Settings → Garde."))
                }
                List {
                    if captured.isEmpty { Text("Nothing scanned yet").foregroundStyle(.secondary) }
                    ForEach($captured) { $c in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                if !c.resolved { ProgressView().controlSize(.small) }
                                TextField("Name", text: $c.name).font(.body.weight(.medium))
                            }
                            HStack {
                                Text(c.category.label)
                                if let e = c.expiration { Text("· exp. \(e.formatted(date: .abbreviated, time: .omitted))") }
                            }.font(.caption).foregroundStyle(.secondary)
                            if !c.allergyWarning.isEmpty {
                                Label("Contains \(c.allergyWarning.joined(separator: ", "))", systemImage: "exclamationmark.triangle.fill")
                                    .font(.caption.weight(.semibold)).foregroundStyle(.red)
                            }
                        }
                    }
                    .onDelete { captured.remove(atOffsets: $0) }
                }
                .frame(height: 260)
            }
            .task {
                switch AVCaptureDevice.authorizationStatus(for: .video) {
                case .authorized: cameraAllowed = true
                case .notDetermined: cameraAllowed = await AVCaptureDevice.requestAccess(for: .video)
                default: cameraAllowed = false
                }
            }
            .gardePage()
            .navigationTitle("Live scan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Add \(captured.count)") { save() }.disabled(captured.isEmpty) }
            }
        }
    }

    private func handleBarcode(_ code: String) {
        guard !seen.contains(code) else { return }
        seen.insert(code)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        captured.insert(Captured(code: code, name: "Looking up \(code)…", category: .other), at: 0)
        Task {
            let product = await BarcodeLookup.lookup(code)
            guard let i = captured.firstIndex(where: { $0.code == code }) else { return }
            if let product {
                captured[i].name = [product.brand, product.name, product.size].filter { !$0.isEmpty }.joined(separator: " ")
                captured[i].category = product.category
                let allergies = profiles.first?.allergies ?? []
                captured[i].allergyWarning = AllergenGuard.violations(in: [product.name] + product.allergens, allergies: allergies)
            } else {
                captured[i].name = ""   // unknown product: let you type it
            }
            captured[i].resolved = true
        }
    }

    private func handleText(_ text: String) {
        guard let date = DateSniffer.date(in: text), !captured.isEmpty else { return }
        captured[0].expiration = date
        dateHint = "Set \(date.formatted(date: .abbreviated, time: .omitted)) on \(captured[0].name.isEmpty ? "last item" : captured[0].name)"
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    private func save() {
        for c in captured where !c.name.trimmingCharacters(in: .whitespaces).isEmpty {
            let loc = ShelfLife.defaultLocation(for: c.category, name: c.name)
            let item = PantryItem(name: c.name, category: c.category, location: loc,
                                  expirationDate: c.expiration ?? ShelfLife.estimatedExpiration(name: c.name, category: c.category, in: loc),
                                  expirationIsEstimated: c.expiration == nil)
            item.barcode = c.code
            context.insert(item)
        }
        ShoppingBrain.checkOff(names: captured.map(\.name), context: context)
        dismiss()
    }
}

/// Finds a printed expiration date like "BEST BY 11/18/26", "EXP 2026-11-18", "NOV 18 2026", "18NOV26".
/// If several dates are printed (e.g. packed + use-by), the latest one is the expiration.
enum DateSniffer {
    static let months = ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"]

    static func date(in raw: String) -> Date? {
        let s = raw.uppercased()
        var found: [Date] = []
        for m in s.matches(of: /(\d{4})[-\/.](\d{1,2})[-\/.](\d{1,2})/) {
            if let y = Int(m.1), let mo = Int(m.2), let d = Int(m.3), let date = make(y, mo, d) { found.append(date) }
        }
        for m in s.matches(of: /\b(\d{1,2})[-\/.](\d{1,2})[-\/.](\d{4}|\d{2})\b/) {
            if let mo = Int(m.1), let d = Int(m.2), let y = Int(m.3), let date = make(y, mo, d) { found.append(date) }
        }
        for m in s.matches(of: /(\d{1,2})\s*(JAN|FEB|MAR|APR|MAY|JUN|JUL|AUG|SEP|OCT|NOV|DEC)[A-Z]*\.?\s*(\d{4}|\d{2})\b/) {
            if let d = Int(m.1), let mo = months.firstIndex(of: String(m.2)), let y = Int(m.3), let date = make(y, mo + 1, d) { found.append(date) }
        }
        for m in s.matches(of: /(JAN|FEB|MAR|APR|MAY|JUN|JUL|AUG|SEP|OCT|NOV|DEC)[A-Z]*\.?\s*(\d{1,2})(?:,\s*|\s+)(\d{4}|\d{2})\b/) {
            if let mo = months.firstIndex(of: String(m.1)), let d = Int(m.2), let y = Int(m.3), let date = make(y, mo + 1, d) { found.append(date) }
        }
        return found.max()
    }

    private static func make(_ y: Int, _ m: Int, _ d: Int) -> Date? {
        let year = y < 100 ? 2000 + y : y
        guard (1...12).contains(m), (1...31).contains(d), (2020...2040).contains(year) else { return nil }
        var comps = DateComponents(year: year, month: m, day: d)
        comps.calendar = Calendar.current
        return comps.isValidDate ? comps.date : nil
    }
}

struct ScannerRepresentable: UIViewControllerRepresentable {
    var onBarcode: (String) -> Void
    var onText: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let vc = DataScannerViewController(recognizedDataTypes: [.barcode(symbologies: [.ean13, .ean8, .upce, .code128]), .text()],
                                           qualityLevel: .balanced, recognizesMultipleItems: true,
                                           isHighFrameRateTrackingEnabled: false, isHighlightingEnabled: true)
        vc.delegate = context.coordinator
        return vc
    }
    func updateUIViewController(_ vc: DataScannerViewController, context: Context) {
        // Start once the scanner is actually on screen.
        if !vc.isScanning { DispatchQueue.main.async { try? vc.startScanning() } }
    }
    static func dismantleUIViewController(_ vc: DataScannerViewController, coordinator: Coordinator) { vc.stopScanning() }
    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let parent: ScannerRepresentable
        init(_ p: ScannerRepresentable) { parent = p }
        func dataScanner(_ s: DataScannerViewController, didAdd items: [RecognizedItem], allItems: [RecognizedItem]) {
            for item in items { if case .barcode(let b) = item, let v = b.payloadStringValue { parent.onBarcode(v) } }
        }
        func dataScanner(_ s: DataScannerViewController, didTapOn item: RecognizedItem) {
            switch item {
            case .text(let t): parent.onText(t.transcript)
            case .barcode(let b): if let v = b.payloadStringValue { parent.onBarcode(v) }
            @unknown default: break
            }
        }
    }
}
