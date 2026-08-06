import SwiftUI

@main
struct MapleSEAInstallerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var pipeline = InstallPipeline(region: .sea)

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(pipeline)
        }
        .windowResizability(.contentSize)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // The app is launched via `swift run` or from a bundle; when run as a bare
        // executable it has no Dock presence unless activated explicitly.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
