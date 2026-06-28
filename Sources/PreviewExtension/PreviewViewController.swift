//  PreviewViewController.swift
//  PreviewExtension
//
//  Quick Look *preview* extension (the large window shown when you press SPACE
//  in the Finder). It conforms to QLPreviewingController and simply shows the
//  embedded thumbnail (extracted by ThumbnailCore) in an NSImageView scaled
//  proportionally to fit. v1 deliberately does NOT render the 3D mesh.

import Cocoa
import Quartz

class PreviewViewController: NSViewController, QLPreviewingController {

    private let imageView = NSImageView()

    override func loadView() {
        let container = NSView()
        container.wantsLayer = true

        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.imageAlignment = .alignCenter
        container.addSubview(imageView)

        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            imageView.topAnchor.constraint(equalTo: container.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        self.view = container
    }

    func preparePreviewOfFile(at url: URL) async throws {
        guard let image = ThumbnailExtractor.image(for: url) else {
            throw NSError(
                domain: "com.guconstantino.MF3Preview",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey:
                    "No embedded thumbnail found in \(url.lastPathComponent)."])
        }
        await MainActor.run {
            self.imageView.image = image
        }
    }
}
