import Foundation

extension Array {
    subscript(safe index: Int) -> Element? {
        index >= 0 && index < count ? self[index] : nil
    }
}

let version = "0.2.0"

func printUsage() {
    print("""
    kvmwatch — keep a single-display layout sane when a KVM switches a monitor away.

    Usage: kvmwatch [options]

    Modes:
      --status           print current detection state and exit
      --once             evaluate once, apply the configured action, exit
      --detect           watch USB devices live (detected=white, removed=red) to configure the monitor
      --dry-run          log intended actions without applying them

    Options:
      --config <path>    config file (default ~/.config/kvmwatch/config.json)
      --print-config     print the effective config and exit
      --set <key=value>  update a config key (repeatable); creates the file if missing
      -h, --help         show this help
      --version          show version

    Settings live in the config file; use --set to change them.

    First run: the monitor's USB ids are required. Find them with --detect, then:
      kvmwatch --set monitorVid=0xVVVV --set monitorPid=0xPPPP
    """)
}

func failUnconfigured() -> Never {
    let message = """
    kvmwatch: monitor USB device not configured.

      1. Run:  kvmwatch --detect
      2. Switch the KVM away and back — the device that turns red (removed) then
         white (detected) is your monitor.
      3. Configure it:  kvmwatch --set monitorVid=0xVVVV --set monitorPid=0xPPPP

    """
    FileHandle.standardError.write(message.data(using: .utf8)!)
    exit(1)
}

func monitorIDs(_ config: Config) -> (vid: Int, pid: Int) {
    guard let vid = config.monitorVid?.value, let pid = config.monitorPid?.value else {
        failUnconfigured()
    }
    return (vid, pid)
}

struct Options {
    var configPath: String?
    var sets: [String] = []
    var printConfig = false
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
        case "--set": if let pair = next() { options.sets.append(pair) }
        case "--print-config": options.printConfig = true
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

// Config-management commands write the file and exit.
if !options.sets.isEmpty {
    for pair in options.sets {
        guard let eq = pair.firstIndex(of: "=") else {
            FileHandle.standardError.write("kvmwatch: --set expects key=value, got '\(pair)'\n".data(using: .utf8)!)
            exit(2)
        }
        let key = String(pair[..<eq])
        let value = String(pair[pair.index(after: eq)...])
        guard config.set(key: key, value: value) else {
            FileHandle.standardError.write("kvmwatch: invalid --set \(pair) (valid keys: \(Config.settableKeys.joined(separator: ", ")))\n".data(using: .utf8)!)
            exit(2)
        }
    }
    guard config.save(path: options.configPath) else { exit(1) }
    print("updated \(Config.expandedPath(options.configPath)):")
    print(config.encoded())
    exit(0)
}

if options.printConfig {
    print(config.encoded())
    exit(0)
}

switch options.mode {
case "status":
    print(Watcher(config: config, dryRun: true).describe())

case "detect":
    Detect.run(pollSeconds: config.pollSeconds,
               monitorVid: config.monitorVid?.value,
               monitorPid: config.monitorPid?.value)

case "once":
    Log.configure(log: config.log, logPath: config.logPath)
    let ids = monitorIDs(config)
    let watcher = Watcher(config: config, dryRun: options.dryRun)
    Log.line("once :: \(watcher.describe())")
    watcher.act(present: USB.present(vid: ids.vid, pid: ids.pid))

default:
    Log.configure(log: config.log, logPath: config.logPath)
    if !Config.fileExists(path: options.configPath), config.save(path: options.configPath) {
        Log.line("wrote config: \(Config.expandedPath(options.configPath))")
    }
    _ = monitorIDs(config) // exits with guidance if the monitor is not configured
    let watcher = Watcher(config: config, dryRun: options.dryRun)
    watcher.run()
}
