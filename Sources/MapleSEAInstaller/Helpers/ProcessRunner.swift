import Foundation

enum ProcessError: LocalizedError {
    case nonZeroExit(command: String, code: Int32, output: String)

    var errorDescription: String? {
        switch self {
        case .nonZeroExit(let command, let code, let output):
            return "`\(command)` exited with code \(code): \(output.trimmingCharacters(in: .whitespacesAndNewlines))"
        }
    }
}

enum ProcessRunner {
    /// Runs a command to completion, returning combined stdout+stderr.
    @discardableResult
    static func run(_ executable: String, _ arguments: [String], currentDirectory: URL? = nil) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if let currentDirectory { process.currentDirectoryURL = currentDirectory }

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        let output = String(data: data, encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else {
            throw ProcessError.nonZeroExit(
                command: ([executable] + arguments).joined(separator: " "),
                code: process.terminationStatus,
                output: output
            )
        }
        return output
    }

    /// Starts a long-running process without waiting (e.g. the Wine installer).
    static func launch(_ executable: String, _ arguments: [String], environment: [String: String]? = nil) throws -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if let environment {
            process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
        }
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        return process
    }

    /// Runs a shell command with an admin-privileges prompt (native macOS dialog).
    static func runAsAdmin(shellCommand: String) throws {
        let escaped = shellCommand
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let script = "do shell script \"\(escaped)\" with administrator privileges"
        var error: NSDictionary?
        guard let appleScript = NSAppleScript(source: script) else {
            throw ProcessError.nonZeroExit(command: shellCommand, code: -1, output: "Could not build AppleScript")
        }
        appleScript.executeAndReturnError(&error)
        if let error {
            let message = error[NSAppleScript.errorMessage] as? String ?? "\(error)"
            throw ProcessError.nonZeroExit(command: shellCommand, code: -1, output: message)
        }
    }
}
