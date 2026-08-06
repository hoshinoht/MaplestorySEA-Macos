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

    /// Total on-disk size of a directory tree, 0 if it doesn't exist.
    static func directorySize(_ url: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: [.totalFileAllocatedSizeKey]) else { return 0 }
        var total: Int64 = 0
        for case let file as URL in enumerator {
            total += Int64((try? file.resourceValues(forKeys: [.totalFileAllocatedSizeKey]).totalFileAllocatedSize) ?? 0)
        }
        return total
    }

    /// Sets or clears the BSD user-immutable flag (chflags uchg / nouchg).
    static func setImmutable(_ url: URL, _ immutable: Bool) throws {
        try FileManager.default.setAttributes([.immutable: immutable], ofItemAtPath: url.path)
    }
}
