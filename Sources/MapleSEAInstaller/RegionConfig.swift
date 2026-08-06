import Foundation

/// Everything region-specific lives here. Supporting another MapleStory region
/// means adding a new static config, not changing pipeline code.
struct RegionConfig: Sendable {
    let name: String

    /// Page scraped to discover the latest full-client version and file list.
    let downloadPageURL: URL

    /// CDN base, e.g. https://download-maple.playpark.net/full-client/
    /// The versioned folder ("v252") is appended at runtime.
    let fullClientBaseURL: URL

    /// Last version known to exist, used as the floor for CDN probing when the
    /// download page cannot be parsed.
    let lastKnownVersion: Int

    /// Where the client lands inside the Wine bottle (Windows-style, backslashes).
    let windowsInstallDir: String
    let windowsExePath: String

    /// Same paths relative to drive_c, POSIX-style, for existence checks from macOS.
    let installDirRelativeToDriveC: String
    let exeRelativeToDriveC: String

    static let sea = RegionConfig(
        name: "MapleStorySEA",
        downloadPageURL: URL(string: "https://www.maplesea.com/download/gameclient")!,
        fullClientBaseURL: URL(string: "https://download-maple.playpark.net/full-client/")!,
        lastKnownVersion: 252,
        windowsInstallDir: #"C:\Program Files (x86)\Wizet\MapleStorySEA"#,
        windowsExePath: #"C:\Program Files (x86)\Wizet\MapleStorySEA\MapleStory.exe"#,
        installDirRelativeToDriveC: "Program Files (x86)/Wizet/MapleStorySEA",
        exeRelativeToDriveC: "Program Files (x86)/Wizet/MapleStorySEA/MapleStory.exe"
    )
}

/// Fixed locations belonging to the GMS macOS launcher and its Wine bottle.
enum GMSPaths {
    static let launcherApp = URL(fileURLWithPath: "/Applications/MapleStory Launcher.app")

    static let wineBinary = launcherApp
        .appendingPathComponent("Contents/SharedSupport/maplestoryna/MapleStory Launcher/wine")

    static let innerWrapperApp = launcherApp
        .appendingPathComponent("Contents/SharedSupport/maplestoryna/MapleStory.app")

    static let installedWrapperApp = URL(fileURLWithPath: "/Applications/MapleStory.app")

    static var bottleDriveC: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/MapleStoryNA/Bottles/maplestory/drive_c")
    }

    static var launchArgsFile: URL {
        bottleDriveC.appendingPathComponent(".ms-launch-args")
    }

    /// Nexon's public launcher download page (fallback when no direct pkg URL works).
    static let nexonLauncherPage = URL(string: "https://www.nexon.com/main/en/download/launcher")!
}

/// Where this installer keeps its own downloads.
enum InstallerPaths {
    static var supportDir: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/MapleSEAInstaller")
    }

    static func clientDir(version: String) -> URL {
        supportDir.appendingPathComponent(version)
    }
}
