import Foundation
import CoreGraphics

/// Display enumeration and mirroring via the CoreGraphics configuration API.
enum Display {
    static func online() -> [CGDirectDisplayID] {
        var count: UInt32 = 0
        var ids = [CGDirectDisplayID](repeating: 0, count: 32)
        CGGetOnlineDisplayList(32, &ids, &count)
        return Array(ids.prefix(Int(count)))
    }

    static func builtin() -> CGDirectDisplayID? {
        online().first { CGDisplayIsBuiltin($0) != 0 }
    }

    static func external() -> CGDirectDisplayID? {
        online().first { CGDisplayIsBuiltin($0) == 0 }
    }

    static func isMirrored(_ id: CGDirectDisplayID) -> Bool {
        CGDisplayMirrorsDisplay(id) != kCGNullDirectDisplay
    }

    /// Mirror the external display onto `master` (pass nil to unmirror/extend).
    static func setMirror(_ master: CGDirectDisplayID?) -> Bool {
        guard let external = external() else { return false }
        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success, let cfg = config else { return false }
        let err = CGConfigureDisplayMirrorOfDisplay(cfg, external, master ?? kCGNullDirectDisplay)
        if err != .success {
            CGCancelDisplayConfiguration(cfg)
            return false
        }
        return CGCompleteDisplayConfiguration(cfg, .permanently) == .success
    }
}
