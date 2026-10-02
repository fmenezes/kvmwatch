import Foundation

/// An integer that can be written as decimal or `0x`-prefixed hex in JSON,
/// and is always emitted as `0x%04X`.
struct HexInt: Codable, CustomStringConvertible, Equatable {
    let value: Int

    init(_ value: Int) { self.value = value }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let int = try? container.decode(Int.self) {
            value = int
            return
        }
        let string = try container.decode(String.self)
        guard let parsed = HexInt.parse(string) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "invalid integer: \(string)")
        }
        value = parsed
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(String(format: "0x%04X", value))
    }

    var description: String { String(format: "0x%04X", value) }

    static func parse(_ string: String) -> Int? {
        let trimmed = string.trimmingCharacters(in: .whitespaces)
        if trimmed.lowercased().hasPrefix("0x") {
            return Int(trimmed.dropFirst(2), radix: 16)
        }
        return Int(trimmed)
    }
}

struct Config: Codable {
    var monitorVid: HexInt = HexInt(0x0BDA)
    var monitorPid: HexInt = HexInt(0x5450)
    var debounceSeconds: Double = 1.5
    var pollSeconds: Double = 1.0
    var onAway: String = "mirror"
    var onReturn: String = "extend"
    var log: String = "stderr"
    var logPath: String = "~/Library/Logs/kvmwatch.log"

    static var defaultPath: String {
        ("~/.config/kvmwatch/config.json" as NSString).expandingTildeInPath
    }

    enum CodingKeys: String, CodingKey {
        case monitorVid, monitorPid, debounceSeconds, pollSeconds, onAway, onReturn, log, logPath
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        monitorVid = try c.decodeIfPresent(HexInt.self, forKey: .monitorVid) ?? HexInt(0x0BDA)
        monitorPid = try c.decodeIfPresent(HexInt.self, forKey: .monitorPid) ?? HexInt(0x5450)
        debounceSeconds = try c.decodeIfPresent(Double.self, forKey: .debounceSeconds) ?? 1.5
        pollSeconds = try c.decodeIfPresent(Double.self, forKey: .pollSeconds) ?? 1.0
        onAway = try c.decodeIfPresent(String.self, forKey: .onAway) ?? "mirror"
        onReturn = try c.decodeIfPresent(String.self, forKey: .onReturn) ?? "extend"
        log = try c.decodeIfPresent(String.self, forKey: .log) ?? "stderr"
        logPath = try c.decodeIfPresent(String.self, forKey: .logPath) ?? "~/Library/Logs/kvmwatch.log"
    }

    static func load(path: String?) -> Config {
        let expanded = expandedPath(path)
        guard let data = FileManager.default.contents(atPath: expanded) else {
            return Config()
        }
        do {
            return try JSONDecoder().decode(Config.self, from: data)
        } catch {
            Log.line("config parse error (\(expanded)): \(error) — using defaults")
            return Config()
        }
    }

    static func expandedPath(_ path: String?) -> String {
        ((path ?? Config.defaultPath) as NSString).expandingTildeInPath
    }

    static func fileExists(path: String?) -> Bool {
        FileManager.default.fileExists(atPath: expandedPath(path))
    }

    func encoded() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(self) else { return "{}" }
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    @discardableResult
    func save(path: String?) -> Bool {
        let url = URL(fileURLWithPath: Config.expandedPath(path))
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            var text = encoded()
            if !text.hasSuffix("\n") { text += "\n" }
            try text.write(to: url, atomically: true, encoding: .utf8)
            return true
        } catch {
            Log.line("failed to write config (\(url.path)): \(error)")
            return false
        }
    }

    /// Apply a `key=value` pair. Returns false for unknown keys or bad values.
    mutating func set(key: String, value: String) -> Bool {
        switch key {
        case "monitorVid": guard let n = HexInt.parse(value) else { return false }; monitorVid = HexInt(n)
        case "monitorPid": guard let n = HexInt.parse(value) else { return false }; monitorPid = HexInt(n)
        case "debounceSeconds": guard let d = Double(value) else { return false }; debounceSeconds = d
        case "pollSeconds": guard let n = Double(value) else { return false }; pollSeconds = n
        case "onAway": onAway = value
        case "onReturn": onReturn = value
        case "log": log = value
        case "logPath": logPath = value
        default: return false
        }
        return true
    }

    static let settableKeys = ["monitorVid", "monitorPid", "debounceSeconds", "pollSeconds", "onAway", "onReturn", "log", "logPath"]
}
