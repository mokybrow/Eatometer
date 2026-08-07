import SwiftUI
import PhotosUI
import Vision
import UIKit

struct SubmitProductForReviewSheet: View {
    @EnvironmentObject private var catalogService: FoodCatalogService
    @Environment(\.dismiss) private var dismiss

    let userProductID: UUID
    let initialName: String
    let initialBrand: String

    @State private var barcode: String = ""
    @State private var barcodeFormat: String = "EAN13"
    @State private var showBarcodeScanner = false
    @State private var pickedItem: PhotosPickerItem?
    @State private var nutritionImage: UIImage?
    @State private var ocrCalories: String = ""
    @State private var ocrProtein: String = ""
    @State private var ocrFat: String = ""
    @State private var ocrCarbs: String = ""
    @State private var ocrRawText: String = ""
    @State private var isRecognizing = false
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var infoMessage: String?

    private var canSubmit: Bool {
        !barcode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        nutritionImage != nil &&
        !isSubmitting
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("submit_review.section.barcode") {
                    HStack {
                        TextField("submit_review.barcode.placeholder", text: $barcode)
                            .keyboardType(.numberPad)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Button {
                            showBarcodeScanner = true
                        } label: {
                            Image(systemName: "barcode.viewfinder")
                                .imageScale(.large)
                        }
                    }
                    Picker("submit_review.barcode.format", selection: $barcodeFormat) {
                        Text("EAN13").tag("EAN13")
                        Text("EAN8").tag("EAN8")
                        Text("UPCA").tag("UPCA")
                        Text("UPCE").tag("UPCE")
                    }
                    .pickerStyle(.segmented)
                }

                Section("submit_review.section.photo") {
                    if let nutritionImage {
                        Image(uiImage: nutritionImage)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 240)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }

                    PhotosPicker(selection: $pickedItem, matching: .images, photoLibrary: .shared()) {
                        Label(nutritionImage == nil ? "submit_review.photo.choose" : "submit_review.photo.replace", systemImage: "photo.on.rectangle")
                    }

                    if isRecognizing {
                        HStack {
                            ProgressView()
                            Text("submit_review.ocr.running")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("submit_review.section.values") {
                    nutrientField("addmeal.total.calories", text: $ocrCalories)
                    nutrientField("addmeal.total.protein", text: $ocrProtein)
                    nutrientField("addmeal.total.fat", text: $ocrFat)
                    nutrientField("addmeal.total.carbs", text: $ocrCarbs)
                    Text("submit_review.values.hint")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                if !ocrRawText.isEmpty {
                    Section("submit_review.section.raw") {
                        Text(ocrRawText)
                            .font(.caption)
                            .textSelection(.enabled)
                    }
                }
            }
            .navigationTitle("submit_review.title")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.close") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSubmitting {
                        ProgressView()
                    } else {
                        Button("submit_review.submit") {
                            Task { await submit() }
                        }
                        .disabled(!canSubmit)
                    }
                }
            }
            .sheet(isPresented: $showBarcodeScanner) {
                BarcodeScannerView(
                    onScan: { code in
                        barcode = code
                        showBarcodeScanner = false
                    },
                    onCancel: { showBarcodeScanner = false }
                )
            }
            .onChange(of: pickedItem) { _, newValue in
                Task { await loadPickedImage(newValue) }
            }
            .alert("common.error", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("common.ok", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
            .alert("submit_review.success.title", isPresented: Binding(
                get: { infoMessage != nil },
                set: { if !$0 { infoMessage = nil; dismiss() } }
            )) {
                Button("common.ok", role: .cancel) { infoMessage = nil; dismiss() }
            } message: {
                Text(infoMessage ?? "")
            }
        }
    }

    @ViewBuilder
    private func nutrientField(_ key: LocalizedStringKey, text: Binding<String>) -> some View {
        HStack {
            Text(key)
            Spacer()
            TextField("0", text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 96)
        }
    }

    private func loadPickedImage(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else { return }
            await MainActor.run {
                self.nutritionImage = image
            }
            await runOCR(on: image)
        } catch {
            await MainActor.run { errorMessage = String(describing: error) }
        }
    }

    private func runOCR(on image: UIImage) async {
        await MainActor.run { isRecognizing = true }
        defer { Task { @MainActor in isRecognizing = false } }
        guard let cgImage = image.cgImage else { return }
        let recognizedText = await Task.detached { () -> String in
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false
            request.recognitionLanguages = ["ru-RU", "en-US"]
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
                let observations = request.results ?? []
                let lines = observations.compactMap { $0.topCandidates(1).first?.string }
                return lines.joined(separator: "\n")
            } catch {
                return ""
            }
        }.value
        let parsed = NutritionLabelParser.parse(text: recognizedText)
        await MainActor.run {
            self.ocrRawText = recognizedText
            if let v = parsed.calories { self.ocrCalories = format(v) }
            if let v = parsed.protein  { self.ocrProtein  = format(v) }
            if let v = parsed.fat      { self.ocrFat      = format(v) }
            if let v = parsed.carbs    { self.ocrCarbs    = format(v) }
        }
    }

    private func format(_ value: Double) -> String {
        if abs(value - value.rounded()) < 0.05 { return String(format: "%.0f", value) }
        return String(format: "%.1f", value)
    }

    private func parseDouble(_ s: String) -> Double? {
        let cleaned = s.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)
        return Double(cleaned)
    }

    private func submit() async {
        guard let nutritionImage, let encoded = UploadImageCompressor.encodeForUpload(nutritionImage) else {
            errorMessage = "Cannot encode photo"
            return
        }
        let cleanBarcode = barcode.trimmingCharacters(in: .whitespacesAndNewlines)
        await MainActor.run { isSubmitting = true }
        defer { Task { @MainActor in isSubmitting = false } }

        let slots = await catalogService.createSubmissionUploadURLs(
            photos: [(.nutrition, encoded.contentType)]
        )
        guard let nutritionSlot = slots.first(where: { $0.kind == .nutrition }) else {
            await MainActor.run { errorMessage = catalogService.lastErrorMessage ?? "Failed to get upload URL" }
            return
        }
        let uploaded = await catalogService.uploadSubmissionPhoto(slot: nutritionSlot, data: encoded.data, contentType: encoded.contentType)
        guard uploaded else {
            await MainActor.run { errorMessage = catalogService.lastErrorMessage ?? "Upload failed" }
            return
        }

        let submission = await catalogService.submitProductForReview(
            userProductID: userProductID,
            nutritionPhotoKey: nutritionSlot.objectKey,
            barcodePhotoKey: nil,
            packagePhotoKey: nil,
            barcode: cleanBarcode,
            barcodeFormat: barcodeFormat,
            ocrCalories: parseDouble(ocrCalories),
            ocrProtein: parseDouble(ocrProtein),
            ocrFat: parseDouble(ocrFat),
            ocrCarbs: parseDouble(ocrCarbs),
            ocrRawText: ocrRawText.isEmpty ? nil : ocrRawText
        )
        await MainActor.run {
            if submission != nil {
                infoMessage = NSLocalizedString("submit_review.success.message", comment: "")
            } else {
                errorMessage = catalogService.lastErrorMessage ?? "Submit failed"
            }
        }
    }
}

// MARK: - Nutrition label parser

enum NutritionLabelParser {
    struct Result {
        var calories: Double?
        var protein: Double?
        var fat: Double?
        var carbs: Double?
    }

    static func parse(text: String) -> Result {
        var result = Result()
        let lines = text.split(whereSeparator: { $0.isNewline }).map { String($0) }
        for line in lines {
            let lower = line.lowercased()
            if result.calories == nil, matches(lower, keywords: ["ккал", "kcal", "калори", "energy", "энерг"]) {
                if let v = firstNumber(in: line) { result.calories = v }
            }
            if result.protein == nil, matches(lower, keywords: ["белк", "protein", "белок"]) {
                if let v = firstNumber(in: line) { result.protein = v }
            }
            if result.fat == nil, matches(lower, keywords: ["жир", "fat"]) {
                // Avoid matching "trans fat" zeros first; still take first number on the line.
                if let v = firstNumber(in: line) { result.fat = v }
            }
            if result.carbs == nil, matches(lower, keywords: ["углевод", "carbohydrate", "carbs", "carb"]) {
                if let v = firstNumber(in: line) { result.carbs = v }
            }
        }
        return result
    }

    private static func matches(_ line: String, keywords: [String]) -> Bool {
        for k in keywords where line.contains(k) { return true }
        return false
    }

    private static func firstNumber(in s: String) -> Double? {
        // Capture a number with optional comma/dot decimals.
        let pattern = #"(\d+(?:[.,]\d+)?)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(s.startIndex..., in: s)
        guard let match = regex.firstMatch(in: s, range: range), match.numberOfRanges >= 2,
              let r = Range(match.range(at: 1), in: s) else { return nil }
        let raw = s[r].replacingOccurrences(of: ",", with: ".")
        return Double(raw)
    }
}
