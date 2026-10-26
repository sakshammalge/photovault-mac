import AppKit
import SwiftUI

@main
struct PhotoVaultApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var devices: DeviceManager
    @StateObject private var gallery: GalleryModel

    init() {
        let manager = DeviceManager()
        _devices = StateObject(wrappedValue: manager)
        _gallery = StateObject(wrappedValue: GalleryModel(root: manager.backupFolder))
    }

    var body: some Scene {
        WindowGroup("PhotoVault") {
            RootView()
                .environmentObject(devices)
                .environmentObject(gallery)
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
