import AppKit
import SwiftUI

@main
struct EvoWizardApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate
    @State private var keyboard = Keyboard()
    @State private var presets = PresetStore()

    var body: some Scene {
        MenuBarExtra {
            MenuView()
                .environment(keyboard)
                .environment(presets)
        } label: {
            Image(systemName: keyboard.isConnected ? "keyboard.fill" : "keyboard.badge.ellipsis")
        }
        .menuBarExtraStyle(.window)

        Window("EVO75 Keymap", id: "keymap") {
            KeymapView()
                .environment(keyboard)
        }
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(.suppressed)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu-bar only, even when run outside the .app bundle (swift run).
        NSApp.setActivationPolicy(.accessory)
    }
}
