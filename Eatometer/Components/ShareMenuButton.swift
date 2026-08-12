import SwiftUI
import UIKit

/// The toolbar share control, sending the link and the picture together.
///
/// A `ShareLink` rather than a button that presents a share sheet.
/// Most of the screens that can share something are themselves sheets — the
/// meal viewer, the product and recipe pages opened from the library, the meal
/// plan editor — and SwiftUI presents one sheet at a time. A share sheet asked
/// for from inside a sheet is dropped, with "only presenting a single sheet is
/// supported" in the log and nothing at all on screen. `ShareLink` does not go
/// through a presentation binding and so has no such quarrel.
///
struct ShareMenuButton: View {
    /// What is being shared, used only as the local preview title.
    let title: String
    /// The picture to draw. Nil means link only.
    let card: ShareCard?
    /// Makes — or reuses — the link. Nil means the thing cannot be shared.
    let prepare: () async -> URL?

    @State private var url: URL?
    @State private var image: UIImage?
    @State private var didFail = false

    var body: some View {
        content
            // Prepared as the screen opens rather than on the tap, so sharing
            // opens immediately. Sharing the same thing twice reuses the
            // link the service already made, so this does not mint duplicates.
            .task {
                if let card { image = ShareCardRenderer.image(for: card) }
                url = await prepare()
                didFail = url == nil
            }
    }

    @ViewBuilder
    private var content: some View {
        if let url {
            if let image {
                ShareLink(
                    item: Image(uiImage: image),
                    subject: Text(verbatim: ""),
                    message: Text(verbatim: url.absoluteString),
                    preview: SharePreview(title, image: Image(uiImage: image))
                ) {
                    Image(systemName: "square.and.arrow.up")
                }
            } else {
                ShareLink(item: url, subject: Text(verbatim: ""), preview: preview) {
                    Image(systemName: "square.and.arrow.up")
                }
            }
        } else if didFail {
            // Disabled rather than absent: a control that vanishes reads as a
            // bug, one that is there and grey reads as "not for this".
            Image(systemName: "square.and.arrow.up")
                .foregroundStyle(.tertiary)
        } else {
            ProgressView()
                .controlSize(.small)
        }
    }

    private var preview: SharePreview<Image, Never> {
        if let image {
            return SharePreview(title, image: Image(uiImage: image))
        }
        return SharePreview(title, image: Image(AppIconOption.current.previewImageName))
    }
}
