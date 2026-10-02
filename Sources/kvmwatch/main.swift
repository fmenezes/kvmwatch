import Foundation

extension Array {
    subscript(safe index: Int) -> Element? {
        index >= 0 && index < count ? self[index] : nil
    }
}

let version = "0.1.0"

func printUsage() {
    print("""
    kvmwatch — keep a single-display layout sane when a KVM switches a monitor away.

    Usage: kvmwatch [options]

    Modes:
      --status           print current detection state and exit
      --once             evaluate once, apply the configured action, exit
      --detect           list USB devices (vid:pid name) to help configure the monitor
      --dry-run          log intended actions without applying them

    Options (override the config file):
      --config <path>    config file (default ~/.config/kvmwatch/config.json)
      --vid <0xVVVV>     monitor USB vendor id
      --pid <0xPPPP>     monitor USB product id
      --debounce <secs>  settle time before acting (default 1.5)
      --poll <secs>      detection interval (default 1.0)
      --on-away <mode>   mirror | none | notify   (default mirror)
      --on-return <mode> extend | none            (default extend)
      -h, --help         show this help
      --version          show version
    """)
}

struct Options {
    var configPath: String?
    var vid: Int?
    var pid: Int?
    var debounce: Double?
    var poll: Double?
    var onAway: String?
    var onReturn: String?
    var dryRun = false
    var mode = "run"
}

func parse(_ args: [String]) -> Options {
    var options = Options()
    var index = 0
    func next() -> String? { index += 1; return args[safe: index] }
    while index < args.count {
        switch args[index] {
        case "--config": options.configPath = next()
        case "--vid": if let v = next(), let n = HexInt.parse(v) { options.vid = n }
        case "--pid": if let v = next(), let n = HexInt.parse(v) { options.pid = n }
        case "--debounce": if let v = next(), let n = Double(v) { options.debounce = n }
        case "--poll": if let v = next(), let n = Double(v) { options.poll = n }
        case "--on-away": options.onAway = next()
        case "--on-return": options.onReturn = next()
        case "--status": options.mode = "status"
        case "--once": options.mode = "once"
        case "--detect": options.mode = "detect"
        case "--dry-run": options.dryRun = true
        case "-h", "--help": printUsage(); exit(0)
        case "--version": print(version); exit(0)
        default:
            FileHandle.standardError.write("kvmwatch: unknown argument '\(args[index])'\n".data(using: .utf8)!)
            printUsage()
            exit(2)
        }
        index += 1
    }
    return options
}

let options = parse(Array(CommandLine.arguments.dropFirst()))

var config = Config.load(path: options.configPath)
if let v = options.vid { config.monitorVid = HexInt(v) }
if let v = options.pid { config.monitorPid = HexInt(v) }
if let v = options.debounce { config.debounceSeconds = v }
if let v = options.poll { config.pollSeconds = v }
if let v = options.onAway { config.onAway = v }
if let v = options.onReturn { config.onReturn = v }

switch options.mode {
case "status":
    print(Watcher(config: config, dryRun: true).describe())

case "detect":
    for device in USB.all().sorted(by: { ($0.vendorId, $0.productId) < ($1.vendorId, $1.productId) }) {
        print(String(format: "0x%04X:0x%04X  %@", device.vendorId, device.productId, device.name))
    }

case "once":
    let watcher = Watcher(config: config, dryRun: options.dryRun)
    Log.line("once :: \(watcher.describe())")
    watcher.act(present: USB.present(vid: config.monitorVid.value, pid: config.monitorPid.value))

default:
    let watcher = Watcher(config: config, dryRun: options.dryRun)
    watcher.run()
}
