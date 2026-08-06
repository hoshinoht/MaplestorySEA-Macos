import Foundation

enum FileChecks {
    /// Windows executables start with the two-byte "MZ" DOS header.
    static func isPEExecutable(_ url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url),
              let magic = try? handle.read(upToCount: 2) else { return false }
        try? handle.close()
        return magic == Data([0x4D, 0x5A]) // "MZ"
    }

    static func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    /// Sets or clears the BSD user-immutable flag (chflags uchg / nouchg).
    static func setImmutable(_ url: URL, _ immutable: Bool) throws {
        try FileManager.default.setAttributes([.immutable: immutable], ofItemAtPath: url.path)
    }
}
