import Foundation
import Darwin
import os

enum Log {
    private static let subsystem = "com.filipe.kvmwatch"
    private static let osLogger = Logger(subsystem: subsystem, category: "watcher")
    private static let stamp: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    enum Sink { case stderr, unified, file }

    private static var sink: Sink = .stderr
    private static var fileURL: URL?
    private static let maxBytes = 1_000_000

    /// `log`: stderr | unified | file | auto. `auto` = stderr on a TTY, unified otherwise.
    static func configure(log: String, logPath: String) {
        switch log.lowercased() {
        case "unified":
            sink = .unified
        case "file":
            let url = URL(fileURLWithPath: (logPath as NSString).expandingTildeInPath)
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            fileURL = url
            sink = .file
        case "auto":
            sink = isatty(STDERR_FILENO) != 0 ? .stderr : .unified
        default:
            sink = .stderr
        }
    }

    static func line(_ message: String) {
        let text = "[\(stamp.string(from: Date()))] \(message)"
        switch sink {
        case .stderr:
            FileHandle.standardError.write((text + "\n").data(using: .utf8)!)
        case .unified:
            osLogger.log("\(text, privacy: .public)")
        case .file:
            append(text + "\n")
        }
    }

    private static func append(_ text: String) {
        guard let url = fileURL else { return }
        rotateIfNeeded(url)
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(text.data(using: .utf8)!)
            try? handle.close()
        } else {
            try? text.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    private static func rotateIfNeeded(_ url: URL) {
        let fm = FileManager.default
        guard let attrs = try? fm.attributesOfItem(atPath: url.path),
              let size = (attrs[.size] as? NSNumber)?.intValue,
              size >= maxBytes else { return }
        let backup = url.appendingPathExtension("1")
        try? fm.removeItem(at: backup)
        try? fm.moveItem(at: url, to: backup)
    }
}
