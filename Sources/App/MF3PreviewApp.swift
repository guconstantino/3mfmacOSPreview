//  MF3PreviewApp.swift
//  MF3Preview (host app)
//
//  Minimal host application. Its only required job is to *exist in /Applications
//  and be launched once* so macOS registers the embedded Quick Look preview
//  extension. As a convenience it also lets you open a .3mf/.gcode/.bgcode file
//  and see the extracted thumbnail, so you can verify extraction without
//  installing the extension first.

import SwiftUI

@main
struct MF3PreviewApp: App {
    var body: some Scene {
        Window("3MF Preview", id: "main") {
            ContentView()
                .frame(minWidth: 480, minHeight: 420)
        }
        .windowResizability(.contentMinSize)
    }
}
