import LinkPresentation
import SwiftUI
import UIKit

/// Supplies a share payload as a link plus localized accompanying text while
/// providing *local* link metadata. Because the metadata carries no remote
/// image, iOS does not fetch the goeatometer Open Graph card while building the
/// share sheet — so no card is generated at share time, and the same payload
/// works in every target app, not just iMessage.
final class ShareLinkItemSource: NSObject, UIActivityItemSource {
    private let message: String
    private let url: URL
    /// The card, when one was drawn. Used only for the sheet's own preview —
    /// the picture itself travels as a separate activity item.
    private let preview: UIImage?

    init(message: String, url: URL, preview: UIImage? = nil) {
        self.message = message.trimmingCharacters(in: .whitespacesAndNewlines)
        self.url = url
        self.preview = preview
    }

    private var combinedText: String {
        message.isEmpty ? url.absoluteString : "\(message)\n\(url.absoluteString)"
    }

    func activityViewControllerPlaceholderItem(_ controller: UIActivityViewController) -> Any {
        url
    }

    func activityViewController(
        _ controller: UIActivityViewController,
        itemForActivityType activityType: UIActivity.ActivityType?
    ) -> Any? {
        // Copy just the link so it stays a clean URL on the clipboard.
        if activityType == .copyToPasteboard {
            return url
        }
        return message.isEmpty ? url : combinedText
    }

    func activityViewController(
        _ controller: UIActivityViewController,
        subjectForActivityType activityType: UIActivity.ActivityType?
    ) -> String {
        message
    }

    func activityViewControllerLinkMetadata(_ controller: UIActivityViewController) -> LPLinkMetadata? {
        let metadata = LPLinkMetadata()
        metadata.originalURL = url
        metadata.url = url
        metadata.title = message.isEmpty ? url.absoluteString : message
        // The image provider is the card the app drew, if it drew one. Still no
        // remote fetch: iOS never asks goeatometer for an Open Graph card, so
        // the preview is whatever is already in hand and appears immediately.
        if let preview {
            metadata.imageProvider = NSItemProvider(object: preview)
        }
        return metadata
    }
}

struct SystemShareSheetItem: Identifiable {
    let id = UUID()
    let items: [Any]

    /// Localized accompanying text plus the shared link, delivered through a
    /// custom item source so no goeatometer card is generated at share time.
    ///
    /// A drawn card travels alongside as its own item rather than replacing the
    /// link. The picture is what a recipient can read without the app; the link
    /// is what puts the thing into their diary. Neither substitutes for the
    /// other, and a target that only takes one of them still gets something
    /// useful.
    /// Main-actor because drawing the card is. The app target defaults to
    /// `nonisolated`, so without this the renderer would be called from wherever
    /// the caller happens to be — which is the main thread today, by luck of
    /// every call site sitting behind a `@MainActor presentShareSheet()`, and
    /// silently not guaranteed.
    @MainActor
    init(message: String, url: URL, card: ShareCard? = nil) {
        let image = card.map { ShareCardRenderer.image(for: $0) } ?? nil
        var items: [Any] = [ShareLinkItemSource(message: message, url: url, preview: image)]
        if let image { items.append(image) }
        self.items = items
    }

    /// Fallback for payloads that only expose a raw string (e.g. a share code
    /// without a resolvable URL).
    init(message: String, text: String) {
        let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: trimmedText), url.scheme != nil {
            self.items = [ShareLinkItemSource(message: trimmedMessage, url: url)]
        } else {
            let combined = [trimmedMessage, trimmedText].filter { !$0.isEmpty }.joined(separator: "\n")
            self.items = [combined]
        }
    }
}

struct SystemShareSheet: UIViewControllerRepresentable {
    let draft: SystemShareSheetItem
    let onFinish: () -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: draft.items, applicationActivities: nil)
        controller.completionWithItemsHandler = { _, _, _, _ in
            onFinish()
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
