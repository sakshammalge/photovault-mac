import AppKit
import SwiftUI

/// Screenshot/demo mode: `PHOTOVAULT_DEMO_FOLDER=/path` shows that folder instead of any
/// iPhone backup, never talks to a connected phone, and leaves saved settings alone.
/// `PHOTOVAULT_DEMO_SECTION` (gallery, favorites, map, duplicates) picks the first view.
enum Demo {
    static let folder: URL? = ProcessInfo.processInfo.environment["PHOTOVAULT_DEMO_FOLDER"]
        .map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath, isDirectory: true) }
    static let section = ProcessInfo.processInfo.environment["PHOTOVAULT_DEMO_SECTION"]
}

@main
struct PhotoVaultApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var library: DeviceLibrary
    @StateObject private var devices: DeviceManager
    @StateObject private var gallery: GalleryModel

    init() {
        let library = DeviceLibrary()
        _library = StateObject(wrappedValue: library)
        _devices = StateObject(wrappedValue: DeviceManager(library: library))
        // Until a device is chosen the gallery points at a folder that doesn't exist yet.
        let start = Demo.folder ?? library.selected?.folder
            ?? DeviceLibrary.systemPicturesFolder.appendingPathComponent("iPhone", isDirectory: true)
        _gallery = StateObject(wrappedValue: GalleryModel(root: start))
    }

    var body: some Scene {
        WindowGroup("PhotoVault") {
            RootView()
                .environmentObject(library)
                .environmentObject(devices)
                .environmentObject(gallery)
                .frame(minWidth: 760, minHeight: 480)
                .onAppear { if Demo.folder == nil { devices.start() } }
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
