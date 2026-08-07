import SwiftUI
import VisionKit
import Vision
import AVFoundation

struct BarcodeScannerView: UIViewControllerRepresentable {
    let onScan: (String) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onScan: onScan)
    }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let controller = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [
                .ean13,
                .ean8,
                .upce,
                .code128,
                .code39,
                .code93,
                .itf14,
                .qr
            ])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true
        )
        controller.delegate = context.coordinator
        try? controller.startScanning()
        return controller
    }

    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {}

    static func dismantleUIViewController(_ uiViewController: DataScannerViewController, coordinator: Coordinator) {
        uiViewController.stopScanning()
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onScan: (String) -> Void
        private var hasScanned = false

        init(onScan: @escaping (String) -> Void) {
            self.onScan = onScan
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            guard !hasScanned else { return }
            for item in addedItems {
                if case let .barcode(barcode) = item, let payload = barcode.payloadStringValue, !payload.isEmpty {
                    hasScanned = true
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    onScan(payload)
                    return
                }
            }
        }
    }
}

struct BarcodeScannerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onScan: (String) -> Void

    @State private var unavailableReason: String?

    var body: some View {
        NavigationStack {
            Group {
                if let unavailableReason {
                    unavailableView(message: unavailableReason)
                } else {
                    ZStack {
                        BarcodeScannerView(
                            onScan: { code in
                                onScan(code)
                                dismiss()
                            },
                            onCancel: { dismiss() }
                        )
                        .ignoresSafeArea(edges: .bottom)

                        BarcodeScannerOverlay()
                            .ignoresSafeArea(edges: .bottom)
                            .allowsHitTesting(false)
                    }
                }
            }
            .navigationTitle(Text("barcode.scanner.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .platformTopBarLeading) {
                    PressableIconButton(action: { dismiss() }) {
                        Label("common.close", systemImage: "xmark")
                            .labelStyle(.iconOnly)
                            .frame(width: 48, height: 48)
                    }
                    .tint(.primary)
                }
            }
            .task {
                unavailableReason = checkAvailability()
            }
        }
    }

    private func checkAvailability() -> String? {
        guard DataScannerViewController.isSupported else {
            return NSLocalizedString(
                "barcode.scanner.unsupported",
                tableName: nil,
                bundle: .main,
                value: "Barcode scanning is not supported on this device.",
                comment: "Scanner unsupported message"
            )
        }
        guard DataScannerViewController.isAvailable else {
            return NSLocalizedString(
                "barcode.scanner.unavailable",
                tableName: nil,
                bundle: .main,
                value: "Grant camera access to scan barcodes.",
                comment: "Scanner unavailable message"
            )
        }
        return nil
    }

    private func unavailableView(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "barcode.viewfinder")
                .font(.system(size: 64, weight: .light))
                .foregroundStyle(.secondary)
            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct BarcodeScannerOverlay: View {
    var body: some View {
        GeometryReader { proxy in
            let scanRect = scanRect(in: proxy.size)

            ZStack {
                BarcodeScannerCutoutShape(cutout: scanRect, cornerRadius: 18)
                    .fill(Color.black.opacity(0.5), style: FillStyle(eoFill: true))

                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(0.86), lineWidth: 1.5)
                    .frame(width: scanRect.width, height: scanRect.height)
                    .position(x: scanRect.midX, y: scanRect.midY)

                Capsule()
                    .fill(Color.red)
                    .frame(width: scanRect.width - 28, height: 3)
                    .shadow(color: Color.red.opacity(0.55), radius: 8, x: 0, y: 0)
                    .position(x: scanRect.midX, y: scanRect.midY)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }

    private func scanRect(in size: CGSize) -> CGRect {
        let horizontalInset: CGFloat = 32
        let width = min(size.width - horizontalInset * 2, 340)
        let height = min(max(width * 0.46, 132), 170)
        let centerY = size.height * 0.43
        return CGRect(
            x: (size.width - width) / 2,
            y: centerY - height / 2,
            width: width,
            height: height
        )
    }
}

private struct BarcodeScannerCutoutShape: Shape {
    let cutout: CGRect
    let cornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addRect(rect)
        path.addRoundedRect(in: cutout, cornerSize: CGSize(width: cornerRadius, height: cornerRadius))
        return path
    }
}
