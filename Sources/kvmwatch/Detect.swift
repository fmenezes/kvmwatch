import Foundation
import Darwin

/// Live USB monitor: prints devices as they are detected (white) and removed (red).
enum Detect {
    private static let reset = "\u{1B}[0m"
    private static let white = "\u{1B}[97m"
    private static let red = "\u{1B}[31m"
    private static let dim = "\u{1B}[2m"
    private static let bold = "\u{1B}[1m"

    static func run(pollSeconds: Double, monitorVid: Int?, monitorPid: Int?) {
        let color = isatty(STDOUT_FILENO) != 0
        func paint(_ text: String, _ code: String) -> String { color ? code + text + reset : text }
        func stamp() -> String {
            let f = DateFormatter(); f.dateFormat = "HH:mm:ss"
            return f.string(from: Date())
        }
        func tag(_ device: USBDevice) -> String {
            guard let vid = monitorVid, let pid = monitorPid,
                  device.vendorId == vid, device.productId == pid else { return "" }
            return paint("  <= configured monitor", bold)
        }
        func out(_ text: String) {
            print(text)
            fflush(stdout)
        }

        var previous: [String: USBDevice] = [:]
        for device in USB.all() { previous[device.key] = device }

        out(paint("watching USB devices — Ctrl-C to stop (detected = white, removed = red)", dim))
        out(paint("currently attached:", dim))
        for device in previous.values.sorted(by: { $0.label < $1.label }) {
            out("  \(paint("+ \(device.label)", white))\(tag(device))")
        }

        while true {
            Thread.sleep(forTimeInterval: pollSeconds)
            var current: [String: USBDevice] = [:]
            for device in USB.all() { current[device.key] = device }

            for key in current.keys.sorted() where previous[key] == nil {
                let device = current[key]!
                out("[\(stamp())] \(paint("detected  \(device.label)", white))\(tag(device))")
            }
            for key in previous.keys.sorted() where current[key] == nil {
                let device = previous[key]!
                out("[\(stamp())] \(paint("removed   \(device.label)", red))\(tag(device))")
            }
            previous = current
        }
    }
}
