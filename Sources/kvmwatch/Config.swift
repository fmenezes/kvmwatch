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

    static var defaultPath: String {
        ("~/.config/kvmwatch/config.json" as NSString).expandingTildeInPath
    }

    enum CodingKeys: String, CodingKey {
        case monitorVid, monitorPid, debounceSeconds, pollSeconds, onAway, onReturn
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
    }

    static func load(path: String?) -> Config {
        let expanded = ((path ?? Config.defaultPath) as NSString).expandingTildeInPath
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
}
