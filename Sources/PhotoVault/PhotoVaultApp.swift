import AppKit
import SwiftUI

@main
struct PhotoVaultApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var devices = DeviceManager()

    var body: some Scene {
        WindowGroup("PhotoVault") {
            DeviceView()
                .environmentObject(devices)
                .frame(minWidth: 760, minHeight: 480)
                .onAppear { devices.start() }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Needed when launched via `swift run` (no .app bundle) so the window
        // gets a Dock icon and keyboard focus.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
