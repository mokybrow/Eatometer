import UserNotifications
import UIKit

final class NotificationService: UNNotificationServiceExtension {
    private var contentHandler: ((UNNotificationContent) -> Void)?
    private var bestAttemptContent: UNMutableNotificationContent?

    override func didReceive(_ request: UNNotificationRequest, withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        self.contentHandler = contentHandler
        guard let bestAttemptContent = (request.content.mutableCopy() as? UNMutableNotificationContent) else {
            contentHandler(request.content)
            return
        }

        self.bestAttemptContent = bestAttemptContent

        guard let iconValue = request.content.userInfo["meal_slot_icon"] as? String,
              !iconValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            print("NotificationService: no meal_slot_icon in payload")
            contentHandler(bestAttemptContent)
            return
        }

        print("NotificationService: attaching icon", iconValue)
        attachIcon(named: iconValue, to: bestAttemptContent) { [weak self] attached in
            guard let self = self, let bestAttemptContent = self.bestAttemptContent else {
                return
            }
            print("NotificationService: attachment result", attached)
            contentHandler(bestAttemptContent)
        }
    }

    override func serviceExtensionTimeWillExpire() {
        if let contentHandler = contentHandler, let bestAttemptContent = bestAttemptContent {
            contentHandler(bestAttemptContent)
        }
    }

    private func attachIcon(named iconValue: String, to content: UNMutableNotificationContent, completion: @escaping (Bool) -> Void) {
        if let url = URL(string: iconValue), let scheme = url.scheme, scheme.hasPrefix("http") {
            downloadAttachment(from: url) { attachment in
                if let attachment = attachment {
                    content.attachments = [attachment]
                }
                completion(attachment != nil)
            }
            return
        }

        if let attachment = renderSymbolAttachment(named: iconValue) {
            content.attachments = [attachment]
            completion(true)
            return
        }

        completion(false)
    }

    private func downloadAttachment(from url: URL, completion: @escaping (UNNotificationAttachment?) -> Void) {
        let session = URLSession(configuration: .ephemeral)
        let task = session.downloadTask(with: url) { location, _, _ in
            guard let location = location else {
                completion(nil)
                return
            }

            let temporaryURL = self.temporaryFileURL(fileExtension: url.pathExtension.isEmpty ? "png" : url.pathExtension)
            do {
                try FileManager.default.moveItem(at: location, to: temporaryURL)
                let attachment = try UNNotificationAttachment(identifier: "meal_icon", url: temporaryURL, options: nil)
                completion(attachment)
            } catch {
                completion(nil)
            }
        }
        task.resume()
    }

    private func renderSymbolAttachment(named symbolName: String) -> UNNotificationAttachment? {
        let configuration = UIImage.SymbolConfiguration(pointSize: 120, weight: .regular)
        guard let symbolImage = UIImage(systemName: symbolName, withConfiguration: configuration) else {
            return nil
        }

        let canvasSize = CGSize(width: 256, height: 256)
        let renderer = UIGraphicsImageRenderer(size: canvasSize)
        let renderedImage = renderer.image { context in
            UIColor.clear.setFill()
            context.fill(CGRect(origin: .zero, size: canvasSize))

            let symbolSize = symbolImage.size
            let origin = CGPoint(x: (canvasSize.width - symbolSize.width) / 2,
                                 y: (canvasSize.height - symbolSize.height) / 2)
            symbolImage.draw(in: CGRect(origin: origin, size: symbolSize))
        }

        let temporaryURL = temporaryFileURL(fileExtension: "png")
        guard let imageData = renderedImage.pngData() else {
            return nil
        }

        do {
            try imageData.write(to: temporaryURL)
            return try UNNotificationAttachment(identifier: "meal_icon", url: temporaryURL, options: nil)
        } catch {
            return nil
        }
    }

    private func temporaryFileURL(fileExtension: String) -> URL {
        let temporaryDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension(fileExtension)
    }
}
