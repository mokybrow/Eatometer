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

    init(message: String, url: URL) {
        self.message = message.trimmingCharacters(in: .whitespacesAndNewlines)
        self.url = url
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
        // No iconProvider / imageProvider on purpose: iOS renders a plain local
        // preview instead of requesting the generated card from goeatometer.
        return metadata
    }
}

struct SystemShareSheetItem: Identifiable {
    let id = UUID()
    let items: [Any]

    /// Localized accompanying text plus the shared link, delivered through a
    /// custom item source so no goeatometer card is generated at share time.
    init(message: String, url: URL) {
        self.items = [ShareLinkItemSource(message: message, url: url)]
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
