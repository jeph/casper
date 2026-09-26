import AppKit
import SwiftUI

@main
struct CasperApp: App {
    var body: some Scene {
        MenuBarExtra("Casper", systemImage: "waveform") {
            Button("About Casper") {
                // Menu bar apps are never frontmost, so the panel would open behind other windows.
                NSApp.activate()
                NSApp.orderFrontStandardAboutPanel(nil)
            }
            Divider()
            Button("Quit Casper") {
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q")
        }
    }
}
