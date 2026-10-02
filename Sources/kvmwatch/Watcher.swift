import Foundation

final class Watcher {
    private let config: Config
    private let dryRun: Bool
    private let vid: Int
    private let pid: Int
    private var lastPresent: Bool?
    private var pending: DispatchWorkItem?

    init(config: Config, dryRun: Bool) {
        self.config = config
        self.dryRun = dryRun
        self.vid = config.monitorVid?.value ?? 0
        self.pid = config.monitorPid?.value ?? 0
    }

    func describe() -> String {
        let external = Display.external()
        let mirrored = external.map { Display.isMirrored($0) } ?? false
        let state = config.isMonitorConfigured
            ? "usbMonitor=\(USB.present(vid: vid, pid: pid) ? "present" : "absent")"
            : "monitor=unconfigured"
        return "\(state) "
            + "displayCount=\(Display.online().count) "
            + "external=\(external.map { String($0) } ?? "none") "
            + "mirrored=\(mirrored)"
    }

    /// Apply the configured action for a given USB-monitor presence.
    func act(present: Bool) {
        present ? handleReturn() : handleAway()
    }

    func run() {
        lastPresent = USB.present(vid: vid, pid: pid)
        Log.line("kvmwatch started :: \(describe())")
        // If launched while already switched away, fix the ghost immediately.
        if lastPresent == false, let external = Display.external(), !Display.isMirrored(external) {
            execute("startup mirror") { Display.setMirror(Display.builtin()) }
        }
        let timer = Timer.scheduledTimer(withTimeInterval: config.pollSeconds, repeats: true) { [weak self] _ in
            self?.reconcile()
        }
        RunLoop.main.add(timer, forMode: .common)
        RunLoop.main.run()
    }

    // MARK: - private

    private func reconcile() {
        let present = USB.present(vid: vid, pid: pid)
        guard present != lastPresent else { return }
        lastPresent = present
        // Debounce: a real unplug removes the display slightly after the USB
        // device detaches, so wait before deciding whether this is a ghost.
        pending?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.act(present: present) }
        pending = item
        DispatchQueue.main.asyncAfter(deadline: .now() + config.debounceSeconds, execute: item)
    }

    private func handleReturn() {
        guard config.onReturn == "extend" else {
            Log.line("monitor attached -> onReturn=\(config.onReturn), no-op")
            return
        }
        guard let external = Display.external(), Display.isMirrored(external) else {
            Log.line("monitor attached -> already extended, no-op")
            return
        }
        execute("extend") { Display.setMirror(nil) }
    }

    private func handleAway() {
        // Display still present though the monitor's USB is gone => KVM ghost.
        // No display at all => a real unplug, nothing to do.
        guard let external = Display.external() else {
            Log.line("monitor detached, no external display (real unplug) -> no-op")
            return
        }
        switch config.onAway {
        case "mirror":
            guard !Display.isMirrored(external) else {
                Log.line("monitor detached (ghost) -> already mirrored, no-op")
                return
            }
            execute("mirror") { Display.setMirror(Display.builtin()) }
        case "notify":
            execute("notify") { Notification.post("Monitor switched away") }
        default:
            Log.line("monitor detached (ghost) -> onAway=\(config.onAway), no-op")
        }
    }

    private func execute(_ action: String, _ body: () -> Bool) {
        if dryRun {
            Log.line("[dry-run] would \(action)")
            return
        }
        Log.line(body() ? "applied: \(action)" : "FAILED: \(action)")
    }
}
