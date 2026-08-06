import AppKit
import ApplicationServices

/// Auto-advances the InstallShield wizard running under Wine.
///
/// Strategy: Wine draws its own widgets, so the Accessibility tree usually
/// exposes only the window — not the buttons inside it. We try AX buttons
/// first (works if Wine exposes them), and otherwise fall back to pressing
/// Return on the wizard window, which activates InstallShield's default
/// button (Next → Next → Install → Finish are all defaults).
final class WizardClicker: @unchecked Sendable {
    /// Button titles we are willing to press. Anything else (Cancel, Back,
    /// Browse…) is left alone.
    private static let safeButtonTitles: Set<String> = [
        "Next", "Next >", "Next>", "Install", "Finish", "OK", "Yes", "Done",
    ]

    private var timer: Timer?
    private let log: @Sendable (String) -> Void
    private var lastKeypress = Date.distantPast

    init(log: @escaping @Sendable (String) -> Void) {
        self.log = log
    }

    static var hasAccessibilityPermission: Bool {
        AXIsProcessTrusted()
    }

    /// Prompts the system dialog that offers to open Accessibility settings.
    static func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    static func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    func start() {
        stop()
        let timer = Timer(timeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        guard let app = wineInstallerApp() else { return }

        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var windowsRef: CFTypeRef?
        AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsRef)
        let windows = (windowsRef as? [AXUIElement]) ?? []
        guard !windows.isEmpty else { return }

        for window in windows {
            if let button = findSafeButton(in: window) {
                let title = axTitle(of: button) ?? "?"
                if AXUIElementPerformAction(button, kAXPressAction as CFString) == .success {
                    log("Clicked \"\(title)\" in the installer wizard")
                    return
                }
            }
        }

        // Fallback: press Return on the wizard's default button. Throttled so a
        // slow page transition doesn't eat multiple keypresses.
        if Date().timeIntervalSince(lastKeypress) >= 4.0 {
            app.activate()
            postReturnKey(pid: app.processIdentifier)
            lastKeypress = Date()
            log("Pressed Return in the installer wizard (default button)")
        }
    }

    /// The wine process showing the InstallShield window. Under the Crossover
    /// wrapper the GUI process appears as a regular app whose name comes from
    /// the exe ("setup", "wine64-preloader", …).
    private func wineInstallerApp() -> NSRunningApplication? {
        NSWorkspace.shared.runningApplications.first { app in
            guard let name = app.localizedName?.lowercased() else { return false }
            return name.contains("setup") || name.contains("installshield")
                || (name.contains("wine") && app.activationPolicy == .regular)
        }
    }

    private func findSafeButton(in element: AXUIElement, depth: Int = 0) -> AXUIElement? {
        guard depth < 8 else { return nil }
        if axRole(of: element) == kAXButtonRole as String,
           let title = axTitle(of: element),
           Self.safeButtonTitles.contains(title.trimmingCharacters(in: .whitespaces)) {
            return element
        }
        var childrenRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef)
        for child in (childrenRef as? [AXUIElement]) ?? [] {
            if let found = findSafeButton(in: child, depth: depth + 1) {
                return found
            }
        }
        return nil
    }

    private func axRole(of element: AXUIElement) -> String? {
        var value: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &value)
        return value as? String
    }

    private func axTitle(of element: AXUIElement) -> String? {
        var value: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &value)
        return value as? String
    }

    private func postReturnKey(pid: pid_t) {
        let returnKeyCode: CGKeyCode = 36
        guard let down = CGEvent(keyboardEventSource: nil, virtualKey: returnKeyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: returnKeyCode, keyDown: false) else { return }
        down.postToPid(pid)
        up.postToPid(pid)
    }
}
