# kvmwatch

Keep a single-display layout sane when a KVM switch routes your monitor to another machine.

## The problem

When a KVM switches a monitor away to another computer, many KVMs keep the
DisplayPort/HDMI **hot-plug-detect (HPD)** line asserted and the EDID cached. To
macOS the monitor still looks connected and active:

- `CGGetOnlineDisplayList` / `CGGetActiveDisplayList` still report **2** displays
- `system_profiler` still says `Online: Yes`
- **no** CoreGraphics reconfiguration callback fires
- the DCP link never releases

So you get a **ghost display**: macOS keeps extending your desktop onto a screen
that is physically showing a different machine. Windows and the menu bar can end
up "off screen", and `Detect Displays` does nothing about it.

## The fix

`kvmwatch` detects the switch using a signal macOS *does* drop — the monitor's
**USB side**. On a USB-C monitor, the monitor's USB hub + Alt-Mode billboard
detach from this Mac when the KVM routes the monitor away, and re-attach when it
comes back. That detach is a real, observable event.

When the monitor's USB disappears but the display object is still present
(the ghost), `kvmwatch` mirrors the external display onto the built-in so there
is no off-screen desktop. When the monitor's USB returns, it goes back to
extended.

```
monitor USB present                 -> EXTENDED
monitor USB absent, display present -> MIRRORED  (ghost)
monitor USB absent, no display      -> no-op     (real unplug)
```

## Install

### Homebrew

```sh
brew install fmenezes/tap/kvmwatch
```

Then **configure your monitor** (required — the USB ids are machine-specific;
see [Configure](#configure)) and start the service:

```sh
kvmwatch --detect                                       # find the monitor's USB ids
kvmwatch --set monitorVid=0xVVVV --set monitorPid=0xPPPP
brew services start fmenezes/tap/kvmwatch
```

`brew services` starts it now and at login. It is **not** configured to
auto-restart, so if it exits (for example, if started before being configured)
it stays down until you start it again. To stop or restart:

```sh
brew services stop    fmenezes/tap/kvmwatch
brew services restart fmenezes/tap/kvmwatch
```

Uninstall:

```sh
brew services stop fmenezes/tap/kvmwatch
brew uninstall kvmwatch
```

To build and run from source instead (development), see
[Build from source](#build-from-source).

## Build from source

Requirements: **macOS 13 (Ventura) or later** and the Xcode Command Line Tools
(`xcode-select --install`), which provide `swift` (5.9+). No other dependencies.

```sh
git clone https://github.com/fmenezes/kvmwatch.git
cd kvmwatch
swift build -c release
```

The binary is written to `.build/release/kvmwatch`. Run it directly:

```sh
.build/release/kvmwatch --status    # print detection state
.build/release/kvmwatch --detect    # list USB devices to configure
.build/release/kvmwatch             # daemon mode (Ctrl-C to stop)
```

Or via SwiftPM without a separate build step:

```sh
swift run -c release kvmwatch --status
```

To put the built binary on your `PATH`:

```sh
install -m 755 .build/release/kvmwatch /usr/local/bin/kvmwatch
```

For a managed login service, use the Homebrew install above.

## Configure

Config file: `~/.config/kvmwatch/config.json`

```json
{
  "monitorVid": "0x0BDA",
  "monitorPid": "0x5450",
  "debounceSeconds": 1.5,
  "pollSeconds": 1.0,
  "onAway": "mirror",
  "onReturn": "extend",
  "log": "stderr",
  "logPath": "~/Library/Logs/kvmwatch.log"
}
```

| Key | Default | Description |
|---|---|---|
| `monitorVid` / `monitorPid` | **(required)** | USB vendor/product id of the monitor's USB side. No default — the daemon refuses to start until both are set. Run `kvmwatch --detect` and pick the device that disappears when the KVM is switched away (often a `BillBoard Device` or the monitor's USB hub). |
| `debounceSeconds` | `1.5` | settle time before acting; lets a real unplug finish removing the display. |
| `pollSeconds` | `1.0` | detection interval. |
| `onAway` | `mirror` | `mirror` \| `none` \| `notify` |
| `onReturn` | `extend` | `extend` \| `none` |
| `log` | `stderr` | `stderr` \| `unified` \| `file` \| `auto` (see [Logging](#logging)) |
| `logPath` | `~/Library/Logs/kvmwatch.log` | file used when `log=file` |

Settings live in the config file — it is the single source of truth. The file is
created automatically on the first daemon run, but `monitorVid`/`monitorPid` have
**no default**: until both are set, the daemon prints setup instructions and
exits. Manage it from the CLI:

```sh
kvmwatch --print-config                                    # show the effective config
kvmwatch --set monitorVid=0x0BDA --set monitorPid=0x5450   # set the monitor (creates file if absent)
```

`--set` validates keys/values and rewrites the file; after changing it, restart
the service so it re-reads:

```sh
brew services restart fmenezes/tap/kvmwatch
```

## Usage

```sh
kvmwatch                 # run the watcher (this is what launchd starts)
kvmwatch --status        # print current detection state and exit
kvmwatch --once          # evaluate once, apply the action, exit
kvmwatch --detect        # watch USB devices live (detected=white, removed=red)
kvmwatch --dry-run       # log intended actions without applying them
kvmwatch --help
```

## Finding your monitor's USB ids

Run `kvmwatch --detect` and leave it running. It prints the currently attached
USB devices, then streams changes live — **detected** in white, **removed** in
red. Switch the KVM away and back a couple of times: the device that turns red
when you switch away (and white when you switch back) is your monitor's USB
side. Put its `vid:pid` into `monitorVid` / `monitorPid`. The device matching
your current config is marked `<= configured monitor`.

## Logging

Controlled by the `log` setting:

| Value | Where | Inspect with |
|---|---|---|
| `stderr` (default) | stderr; under launchd redirected to `logPath` by the plist | `tail ~/Library/Logs/kvmwatch.log` |
| `unified` | macOS unified logging (`os.Logger`, subsystem `com.filipe.kvmwatch`) | `log stream --predicate 'subsystem == "com.filipe.kvmwatch"'` |
| `file` | appends to `logPath` directly, rotating at ~1 MB (one `.1` backup) | `tail ~/Library/Logs/kvmwatch.log` |
| `auto` | `stderr` when stderr is a TTY, otherwise `unified` | either of the above |

```sh
kvmwatch --set log=unified     # idiomatic macOS unified logging
kvmwatch --set log=file        # plain file with built-in rotation
```

`unified` is the idiomatic macOS choice for a daemon (the OS owns storage and
rotation); `stderr` is the default because it's visible in a terminal too.

## Notes

- `monitorVid`/`monitorPid` have no compiled default (they are machine-specific).
  Until set, the daemon refuses to start and prints setup instructions rather than
  silently doing nothing.
- The display-level APIs cannot see the KVM switch at all — that is why this tool
  keys on USB. See the issue write-up for the measurements.
- The action uses the CoreGraphics display configuration API
  (`CGConfigureDisplayMirrorOfDisplay`) with `permanently`, so state persists.
- macOS-only by nature (CoreGraphics + IOKit + launchd).

## License

MIT
