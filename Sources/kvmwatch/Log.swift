import Foundation

enum Log {
    private static let fmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    static func line(_ message: String) {
        let stamp = fmt.string(from: Date())
        let out = "[\(stamp)] \(message)\n"
        FileHandle.standardError.write(out.data(using: .utf8)!)
    }
}
