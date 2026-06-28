//  ContentView.swift
//  MF3Preview (host app)

import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var image: NSImage?
    @State private var status: String = "Open a .3mf, .gcode or .bgcode file to preview its embedded thumbnail."
    @State private var fileName: String?

    var body: some View {
        VStack(spacing: 16) {
            Text("3MF Preview")
                .font(.title2).bold()
            Text("This app hosts a Quick Look **preview** extension. Keep it in /Applications and launch it once so macOS registers the extension; then press SPACE on a .3mf / .gcode / .bgcode file in the Finder.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal)

            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(nsColor: .underPageBackgroundColor))
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .padding(8)
                } else {
                    Image(systemName: "cube.transparent")
                        .font(.system(size: 64))
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Text(status)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(3)

            Button("Open File…") { openFile() }
                .keyboardShortcut("o", modifiers: .command)
        }
        .padding()
    }

    private func openFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [
            UTType("com.turbozen.3mf"),
            UTType("com.turbozen.gcode"),
            UTType("com.turbozen.bgcode"),
        ].compactMap { $0 }
        panel.allowsOtherFileTypes = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        fileName = url.lastPathComponent
        if let img = ThumbnailExtractor.image(for: url) {
            image = img
            let rep = img.representations.first
            let px = rep.map { "\($0.pixelsWide)×\($0.pixelsHigh)" } ?? "?"
            status = "\(url.lastPathComponent) — embedded thumbnail \(px)"
        } else {
            image = nil
            status = "No embedded thumbnail found in \(url.lastPathComponent)."
        }
    }
}
