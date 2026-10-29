import SwiftUI
import VisionKit

/// El lector de códigos QR dentro de la app (VisionKit): la cámara a pantalla completa, el recuadro al centro y lo que se lee
/// sale por `found` (una vez por código). Si el aparato no puede (el simulador, sin cámara o sin permiso), lo dice y ofrece
/// `fallback` («Conectar a mano»).
struct QRScanner: View {
    let prompt: Text
    let found: (String) -> Void
    let fallback: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            if DataScannerViewController.isSupported && DataScannerViewController.isAvailable {
                ScannerView(found: found).ignoresSafeArea()
                RoundedRectangle(cornerRadius: DS.Radius.lg).strokeBorder(DS.paper, lineWidth: DS.Version.pickedStroke)
                    .frame(width: DS.Guide.scanFrame, height: DS.Guide.scanFrame)
                    .accessibilityHidden(true)
            } else {
                VStack(spacing: DS.Space.s4) {
                    Image(systemName: "camera.metering.unknown").font(DS.TextRecipe.display.font).foregroundStyle(DS.textMuted)
                    Text("Este aparato no puede leer el código.").font(DS.TextRecipe.cardTitle.font).foregroundStyle(DS.text)
                    Button("Conectar a mano") { dismiss(); fallback() }.buttonStyle(.glass)
                }
                .padding(DS.Space.s6)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Backdrop())
        .safeAreaInset(edge: .top) {
            HStack {
                Button("Cancelar") { dismiss() }.buttonStyle(.glass)
                Spacer()
            }
            .padding(.horizontal, DS.Space.s4)
        }
        .safeAreaInset(edge: .bottom) {
            prompt.font(DS.TextRecipe.cardTitle.font).foregroundStyle(DS.paper)
                .padding(.horizontal, DS.Space.s4).padding(.vertical, DS.Space.s2)
                .background(DS.scrim, in: Capsule())
                .padding(.bottom, DS.Space.s6)
        }
    }
}

/// La cámara de VisionKit, solo códigos QR; avisa cada código nuevo.
private struct ScannerView: UIViewControllerRepresentable {
    let found: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(recognizedDataTypes: [.barcode(symbologies: [.qr])], qualityLevel: .balanced,
                                                isHighlightingEnabled: true)
        scanner.delegate = context.coordinator
        try? scanner.startScanning()
        return scanner
    }

    func updateUIViewController(_ controller: DataScannerViewController, context: Context) {}

    static func dismantleUIViewController(_ controller: DataScannerViewController, coordinator: Coordinator) { controller.stopScanning() }

    func makeCoordinator() -> Coordinator { Coordinator(found: found) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let found: (String) -> Void
        private var seen: Set<String> = []
        init(found: @escaping (String) -> Void) { self.found = found }

        func dataScanner(_ scanner: DataScannerViewController, didAdd items: [RecognizedItem], allItems: [RecognizedItem]) {
            for case .barcode(let code) in items {
                guard let text = code.payloadStringValue, seen.insert(text).inserted else { continue }
                found(text)
            }
        }
    }
}
