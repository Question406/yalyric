import Foundation

/// Simple file + console logger for yalyric
public enum YalyricLog {
    private static let maxFileSize: UInt64 = 2 * 1024 * 1024  // 2MB
    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    private static let logFileURL: URL = {
        let logs = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs", isDirectory: true)
        try? FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        return logs.appendingPathComponent("yalyric.log")
    }()

    private static let fileHandle: FileHandle? = {
        let fm = FileManager.default
        let path = logFileURL.path
        if !fm.fileExists(atPath: path) {
            fm.createFile(atPath: path, contents: nil)
        }
        return FileHandle(forWritingAtPath: path)
    }()

    private static let queue = DispatchQueue(label: "com.yalyric.logger", qos: .utility)

    public static func info(_ message: String) {
        log("INFO", message)
    }

    public static func error(_ message: String) {
        log("ERROR", message)
    }

    private static func log(_ level: String, _ message: String) {
        let timestamp = dateFormatter.string(from: Date())
        let line = "[\(timestamp)] [\(level)] \(message)"

        // Console
        print(line)

        // File
        queue.async {
            guard let data = (line + "\n").data(using: .utf8),
                  let handle = fileHandle else { return }
            handle.seekToEndOfFile()
            handle.write(data)

            // Rotate if too large
            if handle.offsetInFile > maxFileSize {
                rotate()
            }
        }
    }

    private static func rotate() {
        let fm = FileManager.default
        let path = logFileURL.path
        let oldPath = path + ".old"
        try? fm.removeItem(atPath: oldPath)
        try? fm.moveItem(atPath: path, toPath: oldPath)
        fm.createFile(atPath: path, contents: nil)
        // Reopen handle — since fileHandle is static let, we can't reassign.
        // The old handle still points to the renamed file. For simplicity,
        // just truncate the current file instead.
        fileHandle?.truncateFile(atOffset: 0)
        fileHandle?.seekToEndOfFile()
    }
}
