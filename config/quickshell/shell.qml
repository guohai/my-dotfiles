// Quickshell bar for niri.
//
// PanelWindow is Quickshell's layer-shell surface (zwlr_layer_shell_v1, which
// niri implements). Variants clones it once per screen so the bar survives
// monitor hotplug without extra wiring.
//
// Quickshell is a toolkit, not a prebuilt shell: the service modules expose
// *data* over D-Bus and you draw the widget yourself. Each needs its daemon
// running -- upower, bluez, NetworkManager and pipewire are all enabled in
// configuration.nix.
//
// The wifi, bluetooth and audio cells are click-to-open pickers. Everything
// they write goes through the service module's own methods, so there is no
// shelling out to nmcli or bluetoothctl anywhere below.

import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.UPower
import Quickshell.Services.Pipewire
import Quickshell.Bluetooth
import Quickshell.Networking
import QtQuick

ShellRoot {
    id: root

    readonly property color bg: "#1e1e2e"
    readonly property color fg: "#cdd6f4"
    readonly property color dim: "#7f849c"
    readonly property color accent: "#89b4fa"
    readonly property color bad: "#f38ba8"
    // Catppuccin Mocha peach. Sits between fg and bad so a warning can be
    // distinguished from an emergency at a glance -- see the battery cell,
    // which is the only thing using it.
    readonly property color warn: "#fab387"
    // Catppuccin Mocha yellow, for a state the machine is being held in on
    // purpose rather than a level it has fallen to. Currently the stay-awake
    // mode on the battery cell.
    //
    // A separate colour rather than reusing warn, even though both mean "look
    // at this": they appear on the same cell, and one peach that means either
    // "the battery is low" or "suspend is inhibited" is a colour you cannot
    // act on without opening the panel to find out which. Yellow reads as a
    // caution next to fg while staying clearly apart from peach.
    readonly property color caution: "#f9e2af"
    readonly property color hover: "#313244"
    readonly property string mono: "JetBrainsMono Nerd Font"

    // The one left inset every panel's content starts at, so headings, rows,
    // chips and prose all share a margin rather than each picking their own.
    // PickerRow is what sets the value: its hover fill spans the full panel
    // width, and text flush against that edge looks cramped -- everything else
    // matches it so the column reads as a column.
    readonly property int inset: 6

    // Nerd Font Material Design glyphs, by codepoint.
    //
    // Icons rather than emoji, deliberately. Emoji come from
    // noto-fonts-color-emoji, which means a bitmap glyph that ignores `color:`
    // -- the accent highlight on an open panel and the red low-battery warning
    // would both stop working. They are also not monospace, so the bar would
    // reflow by a pixel or two as values change. These are monochrome vector
    // glyphs in the same font as the text, so they take the cell's colour and
    // sit on the same baseline.
    //
    // The whole MDI range lives above the BMP (U+F0000+), so a QML string
    // literal would need a surrogate pair -- 󰁹 rather than F0079.
    // Going through fromCodePoint keeps the readable number at the call site.
    // Names below are the nerd-fonts glyphnames.json ones (nf-md-*), so any of
    // them can be looked up on the Nerd Fonts cheat sheet.
    function icon(cp) {
        return String.fromCodePoint(cp);
    }

    // The battery glyph, from the same table the lock screen draws: U+F008E is
    // the empty outline, F007A..F0082 are 10%..90%, F0079 is a full cell and
    // F0084 the charging bolt. nf-md-battery is F0079 and nf-md-battery_10
    // ..._90 run F007A..F0082, which is why the tenths bucket maps to F0079+n
    // for everything in between.
    //
    // One function rather than the expression repeated at each call site,
    // because the bar cell and the lock screen sit side by side every time the
    // machine locks and any disagreement between them reads as a bug in one of
    // them. The lock screen's half of this is levels[] in battext(),
    // nixos/pkgs/swaylock-effects-weekday.patch -- C, so it cannot literally
    // share this code. Keeping the two in step means keeping the table and the
    // percentage that indexes it identical; see info.batPct for the second
    // half, which is the one that was actually out.
    function batGlyph(pct, charging) {
        if (charging)
            return icon(0xF0084);
        const tenths = Math.floor(Math.max(0, Math.min(100, pct)) / 10);
        if (tenths === 0)
            return icon(0xF008E);
        if (tenths >= 10)
            return icon(0xF0079);
        return icon(0xF0079 + tenths);
    }

    // Which popup is open, or "" for none. One string rather than a bool per
    // popup so opening one always closes the others.
    property string openPanel: ""

    // The niri output name of the bar whose cell was last pressed, or "" before
    // anything has been pressed.
    //
    // Only the display picker reads it, for two things that have to agree: the
    // monitor it lists first, and the monitor it opens on. Listing the one you
    // are sitting in front of first is the point -- with an external attached,
    // the settings you want are almost never the ones at the top of an
    // arbitrarily ordered list. But ordering alone would be worse than nothing
    // if the popup then opened on the other screen, so the window is pinned to
    // the same output rather than left for the compositor to place.
    //
    // The bar is cloned per screen, so the cell that was pressed already knows
    // which monitor it is on. That is a better answer than asking niri for the
    // focused output: focus-follows-mouse is off in config.kdl, and a bar is a
    // layer-shell surface that takes no keyboard focus, so pressing the display
    // cell on the external monitor leaves focus wherever it was -- quite
    // possibly the internal panel.
    property string activeOutput: ""

    // Edit this list to change the world clock. Names are tz database zones;
    // `timedatectl list-timezones` prints the valid ones.
    readonly property var zones: [
        { label: "Los Angeles", tz: "America/Los_Angeles" },
        { label: "New York", tz: "America/New_York" },
        { label: "London", tz: "Europe/London" },
        { label: "Shanghai", tz: "Asia/Shanghai" },
        { label: "Tokyo", tz: "Asia/Tokyo" }
    ]

    // Signal meter. signalStrength is 0..1 -- verified against a live scan,
    // where the connected AP read 0.82. Treating it as 0..100 would peg every
    // network at four bars.
    function bars(strength) {
        const n = Math.min(4, Math.max(1, Math.ceil(strength * 4)));
        return "▁▃▅▇".substring(0, n) + "    ".substring(0, 4 - n);
    }

    // Status labels in the pickers read as standalone fragments -- "On",
    // "Locked", "Paired" -- so they carry a leading capital. Most are literals
    // below and could just be typed that way, but ConnectionState.toString()
    // hands back lowercase from the service module, so at least one of them
    // has to be capitalised at runtime. Doing all of them through one helper
    // keeps the transient states matching the settled ones.
    function cap(s) {
        return s ? s.charAt(0).toUpperCase() + s.slice(1) : s;
    }

    // ---- system stats ---------------------------------------------------
    // Quickshell has no cpu/mem/disk module; these come from /proc via
    // FileView. procfs does not emit inotify events, so watchChanges would
    // never fire -- poll with a Timer and reload() instead.
    Scope {
        id: sys

        // -1 and "" mean "no sample yet", and the bar cells hide themselves
        // until one arrives. 0 cannot carry that meaning: an idle machine
        // genuinely reads 0% cpu, and a cell that vanished whenever the box
        // went quiet would be worse than one that starts late. cpu needs two
        // /proc/stat samples before it can say anything at all, so this state
        // is real for the first tick rather than theoretical.
        property real cpuPct: -1
        property real memPct: -1
        property string diskPct: ""

        // /proc/stat is cumulative since boot, so one read says nothing.
        // Keep the previous sample and report the delta.
        property real prevIdle: 0
        property real prevTotal: 0

        FileView {
            id: statFile
            path: "/proc/stat"
            onLoaded: {
                const f = text().split("\n")[0].split(/\s+/).slice(1).map(Number);
                const idle = f[3] + f[4];
                const total = f.reduce((a, b) => a + b, 0);
                const dIdle = idle - sys.prevIdle;
                const dTotal = total - sys.prevTotal;
                if (sys.prevTotal > 0 && dTotal > 0)
                    sys.cpuPct = 100 * (1 - dIdle / dTotal);
                sys.prevIdle = idle;
                sys.prevTotal = total;
            }
        }

        FileView {
            id: memFile
            path: "/proc/meminfo"
            onLoaded: {
                const t = text();
                // MemAvailable, not MemFree: MemFree excludes reclaimable page
                // cache and makes every healthy Linux box look 95% full.
                const grab = k => Number(t.match(new RegExp(k + ":\\s+(\\d+)"))[1]);
                sys.memPct = 100 * (1 - grab("MemAvailable") / grab("MemTotal"));
            }
        }

        Process {
            id: dfProc
            command: ["df", "--output=pcent", "/"]
            stdout: StdioCollector {
                // df prints a header line then the figure. Guard the index:
                // if df fails or writes nothing, [1] is undefined and .trim()
                // throws, which would leave the cell showing the last good
                // reading forever with no sign it had gone stale.
                onStreamFinished: sys.diskPct = (text.split("\n")[1] ?? "").trim()
            }
        }

        Timer {
            interval: 3000
            running: true
            repeat: true
            triggeredOnStart: true
            onTriggered: {
                statFile.reload();
                memFile.reload();
                dfProc.running = true;
            }
        }
    }

    // ---- system info ----------------------------------------------------
    // Everything the system page shows, gathered by two shell scripts rather
    // than a drawer full of FileViews. Most of these are one-line sysfs files
    // that only mean something in combination -- the GPU name is two PCI ids
    // read out of sysfs and then handed to hwdb, battery health is two files
    // divided by each other -- and a FileView each would put that stitching in
    // QML with nothing ordering the loads against one another.
    //
    // Static and volatile are split because almost none of this moves. Model,
    // CPU, kernel, firmware are fixed until reboot and are read once; battery,
    // uptime, load and disk are re-read on a timer that only runs while the
    // page is open.
    //
    // Both scripts are template literals: do not write a ${ inside one. That is
    // JS interpolation and the shell never sees it. $( and $(( are fine.
    Scope {
        id: info

        property var stat: ({})
        property var live: ({})

        // upower supplies the battery's state and its time estimates. It does
        // not supply the percentage any more -- see batPct below.
        //
        // The kernel's own `capacity` attribute is the trap, and neither source
        // uses it. On this battery it is charge_now/charge_full_design, so it
        // reports how full the cell is as a fraction of what it held when new,
        // and can never reach 100: it reads 53 where the other two say 66 and
        // 68. Everything that shows a battery percentage divides by
        // charge_full instead.
        //
        // Cycle count still comes from sysfs. upower does not expose it.
        readonly property var bat: UPower.displayDevice
        readonly property bool batPresent: bat && bat.isLaptopBattery

        // Health has to come off the real BAT0 entry rather than displayDevice.
        // displayDevice is a synthetic aggregate: it carries state, percentage
        // and energy-full, but not energy-full-design, so healthSupported is
        // false on it and healthPercentage reads 0.
        //
        // healthPercentage is on a 0-100 scale -- 80.02 here -- while
        // percentage on the same object is 0-1. That asymmetry is upstream's,
        // not a typo: do not "fix" one to match the other.
        readonly property var batDev: {
            const ds = UPower.devices ? UPower.devices.values : [];
            for (const d of ds)
                if (d.isLaptopBattery)
                    return d;
            return null;
        }

        // The percentage, read off sysfs with the lock screen's arithmetic
        // instead of taken from upower, because the two do not agree and the
        // lock screen is the one that cannot be changed from here.
        //
        // Measured on this machine, discharging: charge_now/charge_full is
        // 2516000/3704000 = 68%, upower says 65.5%. Both are defensible and
        // neither is the kernel's broken `capacity`. The gap is voltage:
        // sysfs publishes charge_* in uAh only, so upower multiplies by
        // voltage_now to get energy while dividing by an energy_full taken at
        // a higher resting voltage. A sagging cell therefore reads low there
        // and does not here. The gap widens as the battery drains, which is
        // exactly when the number is looked at.
        //
        // Two points is enough to cross a tenths boundary, and when it does
        // the glyphs disagree too -- the bar showing one bar more or less than
        // the screen it was unlocked from seconds earlier. That is the whole
        // reason this moved.
        //
        // The cost, stated plainly: the bar no longer matches `upower -i`, or
        // anything else reading upower. It matches the lock screen instead.
        // That is the trade that was asked for, and only one of the two can be
        // matched at a time.
        property int batNow: -1
        property int batFull: -1

        readonly property int batPct: {
            if (!batPresent)
                return -1;
            // upower is the fallback, not the source: if the sysfs pair is
            // missing the bar shows a slightly different number rather than
            // nothing. The lock screen falls back the same way, to `capacity`.
            if (batNow >= 0 && batFull > 0)
                return Math.max(0, Math.min(100, Math.round(batNow * 100 / batFull)));
            return Math.max(0, Math.min(100, Math.round(bat.percentage * 100)));
        }

        // FileView rather than another poll: reading two sysfs files costs no
        // process, where the liveProc below forks a shell. That matters here
        // and not there, because the bar is always on screen and liveProc only
        // runs while the system page is open.
        //
        // Paths come from statProc because they have to be discovered -- BAT0
        // against BAT1, charge_* against energy_* -- and discovery is a
        // one-shot job that a FileView cannot do for itself.
        FileView {
            id: batNowFile
            path: info.stat.batNowPath || ""
            printErrors: false
            onLoaded: info.batNow = Number(text())
            onLoadFailed: info.batNow = -1
        }

        FileView {
            id: batFullFile
            path: info.stat.batFullPath || ""
            printErrors: false
            onLoaded: info.batFull = Number(text())
            onLoadFailed: info.batFull = -1
        }

        // upower's own update is the clock. sysfs files raise no inotify event
        // on change, so watchChanges would never fire -- checked on the real
        // files, not assumed -- and a timer of our own would be a second, worse
        // guess at a cadence upower already has. When it says the charge moved,
        // re-read the files it moved in.
        //
        // No loop: reloading these does not touch upower.
        Connections {
            target: UPower.displayDevice
            function onPercentageChanged() {
                batNowFile.reload();
                batFullFile.reload();
            }
        }

        // key=value, one per line. Split on the first = only -- the DMI strings
        // and os-release values can contain their own.
        function parse(t) {
            const o = {};
            for (const line of t.split("\n")) {
                const i = line.indexOf("=");
                if (i > 0)
                    o[line.slice(0, i)] = line.slice(i + 1);
            }
            return o;
        }

        function gibN(kb) {
            return (Number(kb) / 1048576).toFixed(1);
        }

        function gib(kb) {
            return info.gibN(kb) + " GiB";
        }

        function dur(sec) {
            const s = Number(sec);
            const d = Math.floor(s / 86400);
            const h = Math.floor(s % 86400 / 3600);
            const m = Math.floor(s % 3600 / 60);
            if (d > 0)
                return d + "d " + h + "h";
            return h > 0 ? h + "h " + m + "m" : m + "m";
        }

        // "Intel(R) Core(TM) i7-7660U CPU @ 2.50GHz" is the string the vendor
        // put in cpuid, not a string anyone wants to read.
        function cpuName(s) {
            return s.replace(/\((R|TM)\)/g, "").replace(" CPU", "").replace(/\s+/g, " ").trim();
        }

        // hwdb answers with the full PCI database entry, "Kaby Lake-U GT3 [Iris
        // Plus Graphics 640]". The bracketed half is the name the part is sold
        // under; the rest is the die it happens to be cut from.
        function gpuName(s) {
            const m = s.match(/\[([^\]]+)\]/);
            return m ? m[1] : s;
        }

        // Version strings carry a parenthetical saying who packaged them, which
        // is the same answer for everything on this machine.
        function short(s) {
            return s.replace(/\s*\(.*\)\s*$/, "");
        }

        // DMI dates are US order and unlabelled, so 06/02/2023 is a coin flip
        // between June and February until it is written out in full.
        function isoDate(s) {
            const m = s.match(/^(\d\d)\/(\d\d)\/(\d\d\d\d)$/);
            return m ? m[3] + "-" + m[1] + "-" + m[2] : s;
        }

        // The two row lists the page renders. Built here rather than in the
        // panel so the formatting lives next to the data it formats, and so a
        // row whose source is missing drops out of the list entirely instead of
        // rendering a label with nothing after it.
        readonly property var hardware: {
            const s = info.stat;
            const v = info.live;
            const r = [];
            const add = (k, val) => {
                if (val)
                    r.push({
                        k: k,
                        v: val
                    });
            };

            add("Model", s.model && s.vendor ? s.model + "   " + s.vendor : s.model);
            add("CPU", s.cpu ? info.cpuName(s.cpu) + "   " + s.cores + " cores / " + s.threads + " threads" : "");
            add("Graphics", s.gpu ? info.gpuName(s.gpu) : "");
            add("Memory", s.memTotal ? info.gib(s.memTotal) + (Number(s.swapTotal) > 0 ? "   " + info.gib(s.swapTotal) + " swap" : "   no swap") : "");
            add("Storage", s.diskModel);
            add("Volume", s.rootFs && v.diskSize ? s.rootFs + "   " + info.gibN(v.diskUsed) + " of " + info.gib(v.diskSize) + " used (" + v.diskPct + ")" : s.rootFs);
            add("Battery", info.batPresent ? info.batPct + "%   " + root.cap(UPowerDeviceState.toString(info.bat.state)) + (v.acOnline === "1" ? "   AC connected" : "") : "");
            // Health and cycles are the thing this page exists to surface that
            // nothing else on the bar does. Either half can be missing without
            // taking the other with it.
            const cond = [];
            if (info.batDev && info.batDev.healthSupported)
                cond.push(Math.round(info.batDev.healthPercentage) + "% of design capacity");
            if (v.batCycles)
                cond.push(v.batCycles + " cycles");
            add("Condition", cond.join("   "));
            // "off" rather than "0 rpm": on this chassis the fan genuinely
            // stops when the machine is cool, and 0 rpm reads like a failed
            // sensor. Raw rpm rather than a percentage of the 1200-7200 range,
            // because the floor is 1200 -- a bar that jumped from empty to a
            // fifth full the moment the fan moved at all would be worse than
            // the number. Whole row drops out if there is no fan sensor.
            add("Cooling", v.fanRpm !== undefined ? (v.fanLabel ? v.fanLabel + "   " : "") + (Number(v.fanRpm) > 0 ? v.fanRpm + " rpm" : "off") : "");
            add("Firmware", s.firmware ? s.firmware + (s.firmwareDate ? "   " + info.isoDate(s.firmwareDate) : "") : "");
            return r;
        }

        readonly property var software: {
            const s = info.stat;
            const v = info.live;
            const r = [];
            const add = (k, val) => {
                if (val)
                    r.push({
                        k: k,
                        v: val
                    });
            };

            add("OS", s.os);
            // The nixpkgs revision the running system was built from. This is
            // the only version here that identifies an exact tree rather than a
            // release, so it is the one to quote in a bug report.
            add("Build", s.build);
            add("Kernel", s.kernel);
            add("Compositor", s.compositor ? info.short(s.compositor) : "");
            add("Shell", s.shell ? info.short(s.shell) : "");
            add("Hostname", s.host);
            add("Uptime", v.uptime ? info.dur(v.uptime) : "");
            add("Load", v.load);
            return r;
        }

        Process {
            id: statProc
            running: true
            command: ["sh", "-c", `
d=/sys/devices/virtual/dmi/id
echo "model=$(cat $d/product_name 2>/dev/null)"
echo "vendor=$(cat $d/sys_vendor 2>/dev/null)"
echo "firmware=$(cat $d/bios_version 2>/dev/null)"
echo "firmwareDate=$(cat $d/bios_date 2>/dev/null)"
echo "cpu=$(awk -F': ' '/^model name/{print $2; exit}' /proc/cpuinfo)"
echo "cores=$(awk -F': ' '/^cpu cores/{print $2; exit}' /proc/cpuinfo)"
echo "threads=$(grep -c ^processor /proc/cpuinfo)"
echo "memTotal=$(awk '/^MemTotal/{print $2; exit}' /proc/meminfo)"
echo "swapTotal=$(awk '/^SwapTotal/{print $2; exit}' /proc/meminfo)"
c=$(ls -d /sys/class/drm/card[0-9] 2>/dev/null | head -1)
if [ -n "$c" ]; then
  id="pci:v0000$(cut -c3- $c/device/vendor | tr a-f A-F)d0000$(cut -c3- $c/device/device | tr a-f A-F)"
  echo "gpu=$(systemd-hwdb query "$id" 2>/dev/null | sed -n 's/^ID_MODEL_FROM_DATABASE=//p')"
fi
for n in /sys/class/nvme/nvme*/model /sys/block/sd*/device/model; do
  if [ -r "$n" ]; then echo "diskModel=$(sed 's/ *$//' $n)"; break; fi
done
echo "rootFs=$(findmnt -no SOURCE,FSTYPE / 2>/dev/null | awk '{print $1"   "$2}')"
# Paths only, not values -- FileView reads these, so nothing here has to run
# again when the charge changes. Preference order mirrors battery_status() in
# nixos/pkgs/swaylock-effects-weekday.patch: first entry whose type is Battery,
# charge_* before energy_*. Written as a list of _now names with _full derived
# by sed because a \${p}_now would close this template literal.
for b in /sys/class/power_supply/*; do
  [ "$(cat $b/type 2>/dev/null)" = Battery ] || continue
  for n in charge_now energy_now; do
    f=$(echo $n | sed s/_now/_full/)
    if [ -r "$b/$n" ] && [ -r "$b/$f" ]; then
      echo "batNowPath=$b/$n"
      echo "batFullPath=$b/$f"
      break
    fi
  done
  break
done
echo "host=$(cat /proc/sys/kernel/hostname)"
echo "kernel=$(cat /proc/sys/kernel/osrelease)"
echo "os=$(. /etc/os-release; echo $PRETTY_NAME)"
echo "build=$(. /etc/os-release; echo $BUILD_ID)"
echo "compositor=$(niri --version 2>/dev/null | head -1)"
echo "shell=$(quickshell --version 2>/dev/null | head -1)"
`]
            stdout: StdioCollector {
                onStreamFinished: info.stat = info.parse(text)
            }
        }

        Process {
            id: liveProc
            // Runs once at startup as well as on the timer, so the first open
            // of the page is already populated rather than filling in a frame
            // later.
            running: true
            command: ["sh", "-c", `
echo "uptime=$(awk '{print int($1)}' /proc/uptime)"
echo "load=$(awk '{print $1"   "$2"   "$3}' /proc/loadavg)"
b=$(ls -d /sys/class/power_supply/BAT* 2>/dev/null | head -1)
if [ -n "$b" ]; then
  echo "batCycles=$(cat $b/cycle_count 2>/dev/null)"
fi
for a in /sys/class/power_supply/A*/online; do
  if [ -r "$a" ]; then echo "acOnline=$(cat $a)"; break; fi
done
# hwmon first because that is where fans live on ordinary hardware; applesmc
# second because on this machine they are not there. Its hwmon node exists but
# carries no fan attributes, so the sensor has to be read off the platform
# device directly -- checked, not assumed. First fan wins; this chassis has one.
# The label is padded with trailing spaces in sysfs.
for f in /sys/class/hwmon/hwmon*/fan?_input /sys/devices/platform/applesmc.*/fan?_input; do
  [ -r "$f" ] || continue
  echo "fanRpm=$(cat $f)"
  echo "fanLabel=$(cat "$(echo $f | sed s/_input/_label/)" 2>/dev/null | sed "s/ *$//")"
  break
done
df -P / 2>/dev/null | awk 'NR==2{print "diskSize="$2; print "diskUsed="$3; print "diskPct="$5}'
`]
            stdout: StdioCollector {
                onStreamFinished: info.live = info.parse(text)
            }
        }

        Timer {
            // Only while the page is open. None of this is shown anywhere else,
            // so polling it closed would be a process every five seconds for
            // something nobody can see.
            interval: 5000
            running: root.openPanel === "system"
            repeat: true
            triggeredOnStart: true
            onTriggered: liveProc.running = true
        }
    }

    // ---- world clock ----------------------------------------------------
    // QML's JS engine has no Intl, and its toLocaleString silently ignores the
    // timeZone option (it returns local time), so neither can do this. Shell
    // out to date(1) instead, which reads the tz database and stays correct
    // across DST changes. One process a minute is not worth optimising.
    Scope {
        id: world
        property var times: ({})

        Process {
            id: tzProc
            command: ["sh", "-c", root.zones.map(z => `TZ=${z.tz} date '+%H:%M %a'`).join("; ")]
            stdout: StdioCollector {
                onStreamFinished: {
                    const lines = text.trim().split("\n");
                    const out = {};
                    root.zones.forEach((z, i) => out[z.label] = lines[i] ?? "--:--");
                    world.times = out;
                }
            }
        }

        Timer {
            interval: 20000
            running: true
            repeat: true
            triggeredOnStart: true
            onTriggered: tzProc.running = true
        }
    }

    // ---- power ----------------------------------------------------------
    // "Stay awake": a logind inhibitor lock held for exactly as long as this
    // process runs. The toggle is `awake.running` and nothing else -- there is
    // no separate bool to fall out of sync with the lock it is supposed to
    // describe.
    //
    // Three things suspend this machine and this blocks two of them, both of
    // which go through logind so one lock covers both:
    //
    //   idle 900s -> `systemctl suspend`   (services.swayidle, configuration.nix)
    //   lid close                          (logind HandleLidSwitch = "suspend")
    //
    // handle-power-key is deliberately absent. Pressing the power key is an
    // explicit request to sleep and swallowing it would be surprising in a way
    // the idle timer and the lid are not -- and it is not logind's to give
    // anyway: niri already holds its own block lock on it, which is visible in
    // `systemd-inhibit --list`.
    //
    // What this does NOT block is the screen going dark, which is the entire
    // point. The 300s lock and the 330s `niri msg action power-off-monitors`
    // are compositor-side rather than logind operations, so no inhibitor
    // reaches them. The machine stays up on the network with the panel black.
    //
    // Releasing the lock *is* the process exiting, so the lock itself never
    // outlives the shell. The *choice* does, via the state file below. The one
    // case neither covers is quickshell being SIGKILLed, which can orphan the
    // child -- it shows up in `systemd-inhibit --list` under the who string
    // below, and `pkill -f 'systemd-inhibit.*Quickshell'` clears it. Worth
    // writing down, because "the laptop stopped sleeping" otherwise has no
    // visible cause.
    Process {
        id: awake
        command: ["systemd-inhibit", "--what=sleep:handle-lid-switch", "--who=Quickshell bar", "--why=Stay awake toggle", "--mode=block", "--", "sleep", "infinity"]
        // Write on every transition, including one the shell did not ask for.
        // If the command fails to start, running falls back to false and this
        // records false -- the file tracks what is actually happening rather
        // than what was last clicked, which is the only way the restored state
        // can be trusted.
        onRunningChanged: awakeState.setText(running ? "1\n" : "0\n")
    }

    // Remembers the choice across shell restarts. Same shape as the monitor
    // state file: atomic writes, absent-on-first-run is not an error, and
    // watchChanges so hand-editing the file works (echo 0 > it, and the mode
    // turns off).
    //
    // Persisting the choice costs a fail-safe, deliberately: a toggle that
    // could not outlive a restart also could not silently pin the laptop
    // awake. This one can, and a machine left on battery with the lid shut
    // will run until it dies. The bar's yellow is the only warning.
    //
    // It does NOT survive a reboot in the way that matters for remote access.
    // Restoring happens when this file loads, and this file only loads once
    // quickshell starts, which is once a graphical session exists -- and login
    // is greetd/tuigreet with no autologin and no lingering user manager. So
    // between boot and someone typing a password, nothing holds the lock and
    // logind's HandleLidSwitch=suspend applies as normal. Reachable with the
    // lid open, gone when it is shut. Making that case work needs the
    // inhibitor to live outside the session entirely (a lingering user unit),
    // which is a configuration.nix change, not a shell one.
    FileView {
        id: awakeState
        path: Quickshell.env("HOME") + "/.local/state/quickshell/stay-awake"
        atomicWrites: true
        printErrors: false
        watchChanges: true
        // watchChanges only raises fileChanged -- it does not reload by itself,
        // which was checked against the running shell rather than assumed. Note
        // the monitors.json FileView above sets watchChanges without this and
        // so is not actually live either; left alone, since nothing depends on
        // it reloading.
        //
        // No loop: the reload calls onLoaded, which sets running to the value
        // it already has, which emits no change, so no write follows.
        onFileChanged: reload()
        onLoaded: awake.running = text().trim() === "1"
        onLoadFailed: awake.running = false
    }

    // ---- audio ----------------------------------------------------------
    // PwObjectTracker is mandatory, not decorative: Quickshell only binds a
    // node's properties while something tracks it. Without this the volume
    // reads zero and never updates.
    PwObjectTracker {
        objects: [Pipewire.defaultAudioSink, Pipewire.defaultAudioSource]
    }

    Scope {
        id: audio
        readonly property var sink: Pipewire.defaultAudioSink
        readonly property var source: Pipewire.defaultAudioSource
        // Real output devices only: isStream filters out per-application
        // playback nodes, which are also sinks in pipewire's model. A
        // bluetooth headset appears here once wireplumber has routed it.
        readonly property var sinks: Pipewire.nodes.values.filter(n => n.isSink && !n.isStream)

        // Inputs need a third test that outputs do not. isSink is true only
        // for real outputs, so !isStream is enough there; !isSink is true for
        // everything that is not an output, which on this machine means the
        // Dummy and Freewheel drivers, the MIDI bridge, a BLE MIDI port and
        // the FaceTime camera -- a video node listed under a heading that says
        // Input. .audio is null for all of them and non-null for the two real
        // capture devices, so it is the discriminator. PwNodeType would say it
        // more directly but does not survive into QML as a usable enum, which
        // would leave a bare `n.type === 9` here.
        readonly property var sources: Pipewire.nodes.values.filter(n => !n.isSink && !n.isStream && n.audio)

        function bump(delta) {
            if (!sink?.audio)
                return;
            sink.audio.muted = false;
            sink.audio.volume = Math.max(0, Math.min(1, sink.audio.volume + delta));
        }

        // Absolute set, for the panel slider. Unmutes for the same reason bump
        // does: dragging the level is asking to hear something, and a drag that
        // moved the fill while the machine stayed silent would look broken.
        //
        // Clamped to 1.0 even though pipewire will happily go past it. The
        // slider has a right-hand end, so anything above it would be a level
        // the bar cannot draw and the drag cannot come back to.
        function setLevel(v) {
            if (!sink?.audio)
                return;
            sink.audio.muted = false;
            sink.audio.volume = Math.max(0, Math.min(1, v));
        }
    }

    // ---- wifi -----------------------------------------------------------
    // The NetworkManager backend attaches asynchronously: for ~3s after launch
    // Networking.devices is empty and wifiEnabled reads false even with the
    // radio up. So everything below is a *binding*, never a one-shot read in
    // Component.onCompleted -- that would latch the pre-init values forever.
    Scope {
        id: net
        readonly property var dev: Networking.devices.values.find(d => d.type === DeviceType.Wifi) ?? null
        readonly property var active: dev ? dev.networks.values.find(n => n.connected) ?? null : null

        // Signal floor for the list below. bars() buckets signalStrength with
        // ceil(strength * 4), so it draws 3 bars once strength * 4 exceeds 2 --
        // "at least 3 bars" is strength > 2/4. Written as 2 / 4 rather than 0.5
        // to keep the 4 of the four-bar meter visible at a glance.
        readonly property real floor: 2 / 4

        // Connected first, then strongest, and only what is worth clicking.
        // filter() already returns a fresh array, so the old .slice() is gone --
        // it was there because .values hands back the live model array and
        // sort() would reorder it in place.
        //
        // The connected network is exempt from the floor. Dropping it when you
        // walk to the far end of the flat would leave the picker with nothing
        // to say about the connection you are actually on, and no way to click
        // it to disconnect.
        readonly property var list: dev ? dev.networks.values.filter(n => n.connected || n.signalStrength > net.floor).sort((a, b) => (b.connected - a.connected) || (b.signalStrength - a.signalStrength)) : []

        // Hidden, not silently dropped -- same reasoning as the "N unnamed"
        // count on the bluetooth scan row. Without this, a scan in a weak spot
        // comes back with an empty list and looks like a dead radio, when in
        // fact it found a dozen APs and none of them cleared 3 bars.
        readonly property int weak: dev ? dev.networks.values.length - net.list.length : 0

        // Network awaiting a passphrase, or null. Set either by clicking an
        // unknown secured network or by a NoSecrets failure.
        property var pskTarget: null
        property string error: ""

        function activate(n) {
            error = "";
            if (n.connected) {
                n.disconnect();
            } else if (n.known || n.security === WifiSecurityType.Open) {
                // known -> NetworkManager already holds the secret in its
                // keyring, so connect() needs no passphrase from us.
                n.connect();
            } else {
                pskTarget = n;
            }
        }

        // ---- DNS override ---------------------------------------------------
        // Which resolver the *active wifi profile* is pinned to. The override
        // lives on the NetworkManager connection, not here and not in
        // /etc/resolv.conf, which buys two things: it survives reboots, and it
        // is remembered per network, so "Cloudflare at the office, DHCP at
        // home" needs no thought after the first time.
        //
        // Nothing in here touches NetBird. It edits one wifi connection
        // profile; NetBird's own registration on wt0 is a separate link and is
        // left exactly alone.
        property string dnsMode: "dhcp"
        property string dnsEffective: ""
        property string dnsCustom: ""
        property bool dnsResolving: true
        property bool dnsBusy: false

        // Address as this machine sees it, and as the internet sees it. The
        // pair is the useful bit: equal means no NAT, different is the normal
        // case, and "local set, public blank" is a good first sign that the
        // way out is broken rather than the link.
        property string localAddr: ""
        property string publicAddr: ""

        // Two addresses per provider rather than one: with a single nameserver
        // any dropped packet is a failed lookup instead of a retry.
        readonly property var dnsPresets: ({
            "google": "8.8.8.8,8.8.4.4",
            "cloudflare": "1.1.1.1,1.0.0.1"
        })

        function dnsServersFor(mode) {
            if (mode === "dhcp")
                return "";
            if (mode === "custom")
                return net.dnsCustom.trim().replace(/[\s,]+/g, ",");
            return net.dnsPresets[mode] ?? "";
        }

        function dnsApply(mode) {
            const servers = net.dnsServersFor(mode);
            // Custom with an empty field is a no-op, not a silent reset to
            // DHCP -- clicking the chip to reveal the input would otherwise
            // wipe the override before anything had been typed into it.
            if (mode === "custom" && servers === "")
                return;
            net.dnsBusy = true;
            dnsWriteProc.servers = servers;
            dnsWriteProc.running = true;
        }

        Process {
            id: dnsWriteProc

            // Passed through the environment rather than interpolated into the
            // script. The Custom field is free text, and "1.1.1.1; rm -rf ~"
            // pasted into a string that becomes `sh -c` is a real hole, not a
            // theoretical one. As an env var it is data to nmcli and nothing
            // else can see it.
            property string servers: ""
            environment: ({
                "DNSSERVERS": servers
            })

            command: ["sh", "-c", `
u=$(nmcli -t -g UUID,TYPE con show --active | awk -F: '$2=="802-11-wireless"{print $1; exit}')
d=$(nmcli -t -g DEVICE,TYPE con show --active | awk -F: '$2=="802-11-wireless"{print $1; exit}')
[ -z "$u" ] && exit 1
if [ -z "$DNSSERVERS" ]; then
  nmcli con modify "$u" ipv4.dns "" ipv4.ignore-auto-dns no
else
  nmcli con modify "$u" ipv4.dns "$DNSSERVERS" ipv4.ignore-auto-dns yes
fi
# reapply pushes the changed IP config onto the live device without tearing
# the association down; con up is the fallback for the cases it refuses
# (it drops the link for a moment, which is why it is not the first choice).
nmcli dev reapply "$d" >/dev/null 2>&1 || nmcli con up "$u" >/dev/null 2>&1
`]

            onExited: dnsReadProc.running = true
        }

        Process {
            id: dnsReadProc

            // Read back rather than trusting what we just wrote, so the chips
            // stay honest if the profile is edited from nmtui or nmcli behind
            // the panel's back.
            command: ["sh", "-c", `
u=$(nmcli -t -g UUID,TYPE con show --active | awk -F: '$2=="802-11-wireless"{print $1; exit}')
d=$(nmcli -t -g DEVICE,TYPE con show --active | awk -F: '$2=="802-11-wireless"{print $1; exit}')
[ -z "$u" ] && exit 0
echo "dns=$(nmcli -t -g ipv4.dns con show "$u")"
# resolvectl first, because once resolved is running it is the only one that
# knows the *per-link* answer. Falling back on an empty result rather than on
# "is the binary present" is deliberate: resolvectl ships on this system
# whether or not resolved is enabled, so testing for the binary would pick a
# branch that silently returns nothing.
eff=$(resolvectl dns "$d" 2>/dev/null | sed 's/^Link [0-9]* ([^)]*): *//')
if [ -z "$eff" ]; then
  # nmcli -t joins a multi-valued field with " | ", which reads as a column
  # rule rather than a separator once it is sitting in a panel. Both branches
  # come out space-separated.
  eff=$(nmcli -t -g IP4.DNS dev show "$d" 2>/dev/null | awk '{printf "%s ", $0}' | sed 's/ *| */ /g')
fi
echo "eff=$eff"
echo "local=$(nmcli -t -g IP4.ADDRESS dev show "$d" 2>/dev/null | head -1)"
# End to end through the real resolver chain, NetBird included -- the point
# is to catch "connected but nothing resolves", which is exactly the state a
# reachable-looking nameserver can still leave you in.
if timeout 3 getent hosts example.com >/dev/null 2>&1; then echo "ok=1"; else echo "ok=0"; fi
`]

            stdout: StdioCollector {
                onStreamFinished: {
                    const o = info.parse(text);
                    net.dnsEffective = (o.eff ?? "").trim();
                    net.localAddr = (o.local ?? "").trim();
                    net.dnsResolving = o.ok === "1";

                    const dns = o.dns ?? "";
                    if (dns === "")
                        net.dnsMode = "dhcp";
                    else if (dns === net.dnsPresets["google"])
                        net.dnsMode = "google";
                    else if (dns === net.dnsPresets["cloudflare"])
                        net.dnsMode = "cloudflare";
                    else {
                        net.dnsMode = "custom";
                        net.dnsCustom = dns;
                    }
                    net.dnsBusy = false;
                }
            }
        }

        Process {
            id: publicIpProc

            // The only thing in this file that talks to a machine outside the
            // network, which is unavoidable: the public address is by
            // definition something only an outside observer can report. Kept
            // deliberately cheap and infrequent -- see the timer for cadence.
            //
            // Two providers because one is a single point of failure for a
            // cosmetic field, and -f so an HTTP error page becomes an empty
            // string rather than being printed as if it were an address.
            command: ["sh", "-c", `
ip=$(curl -sf --max-time 4 https://icanhazip.com 2>/dev/null)
[ -z "$ip" ] && ip=$(curl -sf --max-time 4 https://api.ipify.org 2>/dev/null)
echo "public=$(echo "$ip" | tr -d '[:space:]')"
`]

            stdout: StdioCollector {
                onStreamFinished: net.publicAddr = (info.parse(text).public ?? "").trim()
            }
        }
    }

    // Scan only while the picker is open. A scan wakes the radio and costs
    // power, so leaving scannerEnabled on permanently is a real drain on a
    // laptop. A Binding rather than an assignment so it also switches off if
    // the device disappears.
    Binding {
        target: net.dev
        property: "scannerEnabled"
        value: root.openPanel === "wifi"
        when: net.dev !== null
    }

    // Same reasoning as the scan above: only while the panel is open. Each tick
    // shells out to nmcli twice and makes a real DNS query, which is not
    // something to be doing every five seconds for a panel nobody is looking
    // at. triggeredOnStart so opening the picker shows current state rather
    // than the state from whenever it was last closed.
    Timer {
        interval: 5000
        running: root.openPanel === "wifi"
        repeat: true
        triggeredOnStart: true
        onTriggered: dnsReadProc.running = true
    }

    // The public address gets its own timer rather than riding the one above,
    // because it is the one lookup that leaves the machine. Five seconds would
    // be a request to a third party every five seconds for a number that
    // changes when the network does and not otherwise; five minutes is enough
    // to notice a change while the panel sits open.
    //
    // The short interval is the retry path: an empty result means the last
    // attempt failed, and a failed attempt is usually a connection that just
    // came up and has not settled, which is worth asking about again sooner
    // than five minutes.
    Timer {
        interval: net.publicAddr === "" ? 30000 : 300000
        running: root.openPanel === "wifi"
        repeat: true
        triggeredOnStart: true
        onTriggered: publicIpProc.running = true
    }

    // ---- bluetooth ------------------------------------------------------
    Scope {
        id: bt
        readonly property var adapter: Bluetooth.defaultAdapter
        readonly property var connectedDevices: Bluetooth.devices.values.filter(d => d.connected)

        // A device is yours once it has been paired: bonded, paired, trusted or
        // mid-pairing all count, and a connected one obviously does. These stay
        // in the list whether or not a scan is running -- they are what the
        // picker is actually for.
        function owned(d) {
            return d.connected || d.paired || d.bonded || d.trusted || d.pairing;
        }

        // Everything else in range is a discovery result, and most of it is
        // noise. A scan from a flat picks up around sixty devices, of which
        // eight ever say what they are. The rest are BLE privacy beacons --
        // phones, watches, tags -- advertising a randomised address that
        // rotates every few minutes. bluez still creates a Device1 for each and
        // fills Alias with the MAC in dashes because there is nothing else to
        // put there, which is where rows like "62-C8-07-D8-6F-DA" came from.
        // None of them are pairable and none of them will ever have a name.
        //
        // `deviceName` is bluez's Name property, set only when the device
        // actually broadcast one. `name` is Alias, which always falls back to
        // the MAC -- so Alias can never distinguish the two cases and this has
        // to test Name. Filtering on `icon` instead would be far too harsh:
        // only two of those eight named devices publish one.
        //
        // Not gated on `scanning`. bluez drops untrusted temporaries about
        // thirty seconds after discovery stops, so the list empties itself;
        // gating as well would make named devices vanish the instant the scan
        // was toggled off, which is exactly when the user is reaching for one.
        function nameable(d) {
            return (d.deviceName ?? "") !== "";
        }

        // Connected, then mid-pairing, then paired, then new arrivals.
        //
        // Discovery results are collapsed by name. One physical device commonly
        // advertises from several rotating addresses at once, so a single
        // conference remote in range filled four rows with an identical
        // "MeetUp Soft Remote" and there was no way to tell which to click.
        // Only unpaired results are collapsed -- an owned device always gets
        // its own row, because two of the same headphones is a real thing and
        // silently hiding one of them would make "forget" ambiguous.
        // A function called from the binding rather than a `{ ... }` block
        // binding. QML accepts a statement block as a binding body, but the
        // panel silently rendered as an empty window when this was written that
        // way -- no error, no warning, just nothing. An ordinary expression
        // calling a function is unambiguous, and the dependency on
        // Bluetooth.devices.values is still picked up because the binding reads
        // it. Indexed loop for the same reason: plain array methods are what
        // the rest of this file uses against these service lists.
        function ranked(all) {
            const out = [];
            const seen = [];
            for (let i = 0; i < all.length; i++) {
                const d = all[i];
                const key = d.deviceName ?? "";
                if (bt.owned(d)) {
                    if (key !== "")
                        seen.push(key);
                    out.push(d);
                } else if (bt.nameable(d) && seen.indexOf(key) < 0) {
                    seen.push(key);
                    out.push(d);
                }
            }
            return out.sort((a, b) => (b.connected - a.connected)
                || (b.pairing - a.pairing)
                || (b.paired - a.paired)
                || a.name.localeCompare(b.name));
        }

        readonly property var list: bt.ranked(Bluetooth.devices.values)

        // How many nearby devices the filter is holding back -- anonymous
        // beacons plus collapsed duplicates. Shown next to the scan row so an
        // empty result reads as "nothing here is announcing itself" rather than
        // "the radio is broken".
        readonly property int hidden: Bluetooth.devices.values.length - bt.list.length

        property bool scanning: false

        function activate(d) {
            if (d.connected) {
                d.disconnect();
            } else if (!d.paired) {
                // Needs a bluez agent on the bus to answer the confirmation
                // prompt. Quickshell 0.3.0 registers none, so blueman-applet
                // supplies it (see configuration.nix) -- without an agent this
                // fails with "no agent available".
                d.pair();
            } else {
                // Trust it so bluez reconnects the headset on its own the next
                // time it powers on, which is what macOS does after the first
                // pairing. Idempotent, so setting it on every connect is fine.
                d.trusted = true;
                d.connect();
            }
        }
    }

    Binding {
        target: bt.adapter
        property: "discovering"
        value: bt.scanning && root.openPanel === "bt"
        when: bt.adapter !== null
    }

    // ---- displays -------------------------------------------------------
    // Quickshell has no output-configuration module -- Quickshell.screens is
    // read-only geometry, enough to place a bar on each monitor and nothing
    // more -- so unlike every other picker here this one does shell out. niri
    // owns mode, scale and position, and `niri msg` is its only public way in.
    //
    // The thing to know about `niri msg output` is in its own --help: "The
    // configuration is changed temporarily and not saved into the config file.
    // If the output configuration subsequently changes in the config file,
    // these temporary changes will be forgotten." So niri deliberately does
    // not remember. Anything set here survives until the next config reload or
    // until the monitor is unplugged, and then it is gone.
    //
    // Hence the state file. Every change is written to
    // ~/.local/state/quickshell/monitors.json keyed by the monitor itself, and
    // replayed onto any output that turns up without those settings -- at
    // startup and on every hotplug. That is what makes a monitor come back the
    // way you left it.
    //
    // Keyed by make/model/serial rather than by connector name on purpose. The
    // same monitor is DP-1 or DP-2 depending on which Thunderbolt port it
    // landed in, so a connector-keyed file would forget everything the first
    // time you used the other side of the laptop.
    Scope {
        id: disp

        // Live, from niri. Array of its output objects, with .modes,
        // .current_mode (an index into .modes) and .logical.scale.
        property var outputs: []
        // Remembered. key -> { mode, scale, brightness }.
        property var saved: ({})
        // niri output name -> ddcutil display number, from `ddcutil detect`.
        // Absent means that monitor does not answer DDC and gets no
        // brightness row.
        property var ddc: ({})
        // niri output name -> brightness percent, or absent if unknown.
        property var bright: ({})

        // Set once the state file has been read. Until then restore() must not
        // run: an empty `saved` would look like "nothing remembered" and the
        // first save() would then overwrite the real file with it.
        property bool loaded: false

        readonly property string statePath: Quickshell.env("HOME") + "/.local/state/quickshell/monitors.json"

        // Every output, with the one the picker was opened from moved to the
        // front. `niri msg outputs` returns an object keyed by connector, so
        // the natural order is whatever the JSON happened to enumerate -- which
        // is stable, but has nothing to do with which monitor you are looking
        // at. The rest keep their relative order, so the list does not reshuffle
        // beyond the single move.
        readonly property var list: {
            const arr = outputs ? Object.keys(outputs).map(k => outputs[k]) : [];
            const want = root.activeOutput;
            if (!want)
                return arr;
            const i = arr.findIndex(o => o.name === want);
            // i === 0 is already correct; i === -1 means the bar's screen is not
            // in niri's list, which happens for the moment between a monitor
            // being unplugged and Quickshell.screens catching up.
            return i > 0 ? [arr[i]].concat(arr.slice(0, i), arr.slice(i + 1)) : arr;
        }

        // What a monitor is, independently of where it is plugged in. Falls
        // back to the connector name for a panel that reports no EDID strings
        // at all -- worse than nothing to key on, but better than grouping
        // every such monitor under one empty string.
        function keyOf(o) {
            const id = [o.make, o.model, o.serial].filter(s => s && s.length > 0).join(" ");
            return id.length > 0 ? id : o.name;
        }

        // niri wants "5120x2160@30.000". refresh_rate is millihertz.
        function modeStr(m) {
            return m.width + "x" + m.height + "@" + (m.refresh_rate / 1000).toFixed(3);
        }

        function curMode(o) {
            const m = o.modes[o.current_mode];
            return m ? modeStr(m) : "";
        }

        // One entry per resolution, keeping the highest refresh rate offered
        // for it. The ultrawide advertises 32 modes, most of them the same
        // resolution at 60 / 59.94 / 50 / 30 / 24 -- a list nobody wants to
        // read, and one where the 59.94 next to the 60 is a trap rather than a
        // choice. Sorted by pixel count so the native mode is first.
        //
        // Anything under 1280 wide is dropped outright, at every expansion
        // level. Those are the 800x600 and 720x480 legacy timings every EDID
        // still carries, and picking one on a laptop with no other screen
        // attached is a good way to need a terminal you can no longer read to
        // undo it.
        function allModes(o) {
            const best = {};
            for (const m of o.modes) {
                if (m.width < 1280)
                    continue;
                const k = m.width + "x" + m.height;
                if (!best[k] || m.refresh_rate > best[k].refresh_rate)
                    best[k] = m;
            }
            const out = Object.keys(best).map(k => best[k]);
            out.sort((a, b) => (b.width * b.height) - (a.width * a.height));
            return out;
        }

        // 1080p and below is folded away behind a "show all" row. On this
        // ultrawide that is nine of the thirteen surviving modes -- 1920x1080,
        // 1680x1050, 1600x900, 1440x900, 1366x768, 1280x1024, 1280x800,
        // 1280x720 and so on -- and none of them is a choice anyone plugging in
        // a 5K monitor is looking for. They stay reachable because they are
        // occasionally the point: driving a projector, or matching a capture
        // device that only takes 1080p.
        //
        // Height, not pixel count. An ultrawide 2560x1080 is a 1080p panel in
        // the sense that matters here -- the vertical resolution is what its
        // name is about -- while 1440x1050 has fewer pixels and is not.
        readonly property int collapseBelow: 1080

        function modeList(o) {
            const all = disp.allModes(o);
            if (disp.expanded[o.name])
                return all;
            // The mode currently in use survives the filter whatever its size.
            // Hiding it would leave the section with no highlighted row, which
            // reads as "no resolution is set" rather than "the one you are
            // using is further down".
            const cur = disp.curMode(o);
            const top = all.filter(m => m.height > disp.collapseBelow || disp.modeStr(m) === cur);
            // A monitor whose native mode is itself 1080p would collapse to an
            // empty list, which would leave the section with nothing to click.
            return top.length > 0 ? top : all;
        }

        function hiddenCount(o) {
            return disp.allModes(o).length - disp.modeList(o).length;
        }

        // Keyed by connector and held here rather than in the delegate: the
        // Repeater's model is rebuilt on every refresh, and refresh runs each
        // time the panel opens, so a bool living in the delegate would collapse
        // itself the moment anything else changed.
        property var expanded: ({})

        function toggleExpanded(name) {
            disp.expanded = Object.assign({}, disp.expanded, { [name]: !disp.expanded[name] });
        }

        // ---- talking to niri ----

        property var queue: []
        property bool busy: false

        function run(cmd) {
            disp.queue.push(cmd);
            disp.pump();
        }

        function pump() {
            if (disp.busy || disp.queue.length === 0) {
                // Re-read only once the whole batch has landed. Refreshing
                // after each command would race the next one and, because
                // restore() runs off the refresh, could set a value back to
                // what it was mid-batch.
                if (!disp.busy && disp.queue.length === 0 && disp.pending) {
                    disp.pending = false;
                    disp.refresh();
                }
                return;
            }
            disp.busy = true;
            cmdProc.command = disp.queue.shift();
            cmdProc.running = true;
        }

        property bool pending: false

        function niri(name, action, value) {
            disp.pending = true;
            disp.run(["niri", "msg", "output", name, action, String(value)]);
        }

        function refresh() {
            outputsProc.running = true;
        }

        Process {
            id: cmdProc
            onExited: {
                disp.busy = false;
                disp.pump();
            }
        }

        Process {
            id: outputsProc
            command: ["niri", "msg", "--json", "outputs"]
            stdout: StdioCollector {
                onStreamFinished: {
                    try {
                        disp.outputs = JSON.parse(text);
                    } catch (e) {
                        return;
                    }
                    disp.restore();
                }
            }
        }

        // ---- remembering ----

        FileView {
            id: stateFile
            path: disp.statePath
            // The file is ours alone and rewritten whole, so a partial write is
            // the only corruption worth guarding against -- a truncated JSON
            // would throw on the next parse and lose every monitor's settings
            // at once.
            atomicWrites: true
            // Absent on a first run, which is not an error worth printing.
            printErrors: false
            // FileView caches by path for the life of the process, so without
            // this an edit made outside the shell is never seen -- the cached
            // copy is handed back on every reload. Found the hard way: the file
            // was changed on disk, the shell reloaded, and it kept restoring
            // the previous contents. It also makes hand-editing this file work,
            // which is the only way to clear a remembered monitor.
            watchChanges: true
            onLoaded: {
                try {
                    disp.saved = JSON.parse(text()) || {};
                } catch (e) {
                    disp.saved = {};
                }
                disp.loaded = true;
                disp.refresh();
            }
            onLoadFailed: {
                disp.saved = {};
                disp.loaded = true;
                disp.refresh();
            }
        }

        function remember(o, field, value) {
            const k = disp.keyOf(o);
            const entry = Object.assign({}, disp.saved[k] || {});
            entry[field] = value;
            // Reassign rather than mutate. QML tracks the property, not the
            // object graph underneath it, so an in-place edit updates nothing
            // bound to `saved`.
            disp.saved = Object.assign({}, disp.saved, { [k]: entry });
            stateFile.setText(JSON.stringify(disp.saved, null, 2));
        }

        // Replay whatever is remembered onto whatever is currently attached.
        //
        // Only writes where the live value actually differs, which is what
        // stops this looping: every niri command triggers a refresh, every
        // refresh calls back into here, and the second pass finds nothing left
        // to change. Comparing first rather than setting unconditionally is
        // the whole termination argument.
        function restore() {
            if (!disp.loaded)
                return;
            for (const o of disp.list) {
                const want = disp.saved[disp.keyOf(o)];
                if (!want)
                    continue;
                if (want.mode && want.mode !== disp.curMode(o))
                    disp.niri(o.name, "mode", want.mode);
                if (want.scale && Math.abs(want.scale - o.logical.scale) > 0.001)
                    disp.niri(o.name, "scale", want.scale);
                if (typeof want.brightness === "number" && disp.bright[o.name] !== want.brightness)
                    disp.setBrightness(o, want.brightness, false);
            }
        }

        // ---- brightness ----
        //
        // Two entirely different mechanisms behind one row.
        //
        // The internal panel has a backlight device, and brightnessctl already
        // drives it for the XF86MonBrightness keys (see config.kdl). It works
        // unprivileged because the user is in `video` and the brightnessctl
        // package ships the udev rule.
        //
        // An external monitor has no backlight device anywhere in sysfs. Its
        // brightness lives in the monitor, reachable only by DDC/CI over the
        // I2C channel inside the display cable -- ddcutil, VCP feature 0x10.
        // That needs hardware.i2c.enable and the i2c group, both added in
        // configuration.nix, and a monitor that bothers to implement DDC.
        function isInternal(o) {
            return o.name.indexOf("eDP") === 0 || o.name.indexOf("LVDS") === 0;
        }

        function hasBrightness(o) {
            return disp.isInternal(o) || disp.ddc[o.name] !== undefined;
        }

        function setBrightness(o, pct, store) {
            const v = Math.max(0, Math.min(100, Math.round(pct)));
            if (disp.isInternal(o)) {
                disp.run(["brightnessctl", "--class=backlight", "-q", "set", v + "%"]);
            } else {
                const d = disp.ddc[o.name];
                if (d === undefined)
                    return;
                // --noverify because ddcutil otherwise reads the value back
                // after writing it, doubling an already slow round trip. The
                // bar shows what it asked for, not what it confirmed; a
                // monitor that quietly refuses will look like it worked, which
                // is the price of a row that responds to a click.
                disp.run(["ddcutil", "--display", String(d), "--noverify", "setvcp", "10", String(v)]);
            }
            disp.bright = Object.assign({}, disp.bright, { [o.name]: v });
            if (store !== false)
                disp.remember(o, "brightness", v);
        }

        // brightnessctl -m prints one CSV line:
        //   acpi_video0,backlight,90,100%,90
        // fields: device, class, current, percent, max.
        Process {
            id: brightReadProc
            command: ["brightnessctl", "--class=backlight", "-m"]
            stdout: StdioCollector {
                onStreamFinished: {
                    const f = text.trim().split("\n")[0].split(",");
                    if (f.length < 4)
                        return;
                    const pct = parseInt(f[3]);
                    if (isNaN(pct))
                        return;
                    for (const o of disp.list) {
                        if (disp.isInternal(o))
                            disp.bright = Object.assign({}, disp.bright, { [o.name]: pct });
                    }
                }
            }
        }

        // `ddcutil detect --brief` emits a stanza per display:
        //
        //   Display 1
        //      I2C bus:  /dev/i2c-5
        //      DRM connector: card1-DP-2
        //      Monitor: EVN:V40U46C:0000000000000
        //
        // The DRM connector line is what makes this reliable: card1-DP-2
        // strips to DP-2, which is exactly niri's output name, so the two
        // views of the same monitor are matched on the kernel's identifier
        // rather than on fuzzy EDID string comparison. Older ddcutil builds
        // omit that line, and those displays simply get no brightness row.
        //
        // Detection is slow -- it probes every I2C bus -- so it runs once at
        // startup and again only on hotplug, never on opening the panel.
        Process {
            id: ddcDetectProc
            command: ["ddcutil", "detect", "--brief"]
            stdout: StdioCollector {
                onStreamFinished: {
                    const map = {};
                    let cur = -1;
                    for (const raw of text.split("\n")) {
                        const line = raw.trim();
                        const mDisp = line.match(/^Display\s+(\d+)/);
                        if (mDisp) {
                            cur = parseInt(mDisp[1]);
                            continue;
                        }
                        const mConn = line.match(/^DRM connector:\s*(?:card\d+-)?(\S+)/);
                        if (mConn && cur > 0)
                            map[mConn[1]] = cur;
                    }
                    disp.ddc = map;
                    // Read back what each external panel is actually set to,
                    // so the first open of the picker shows the monitor's own
                    // value rather than a guess.
                    for (const name of Object.keys(map))
                        ddcReadProc.readOne(name, map[name]);
                }
            }
        }

        // getvcp --brief prints: VCP 10 C <current> <max>
        Process {
            id: ddcReadProc
            property var pendingNames: []
            property string activeName: ""

            function readOne(name, display) {
                ddcReadProc.pendingNames.push({ name: name, display: display });
                ddcReadProc.next();
            }
            function next() {
                if (ddcReadProc.running || ddcReadProc.pendingNames.length === 0)
                    return;
                const j = ddcReadProc.pendingNames.shift();
                ddcReadProc.activeName = j.name;
                ddcReadProc.command = ["ddcutil", "--display", String(j.display), "--brief", "getvcp", "10"];
                ddcReadProc.running = true;
            }
            onExited: ddcReadProc.next()
            stdout: StdioCollector {
                onStreamFinished: {
                    const f = text.trim().split(/\s+/);
                    // VCP 10 C <cur> <max>
                    if (f.length >= 5 && f[0] === "VCP") {
                        const cur = parseInt(f[3]);
                        const max = parseInt(f[4]);
                        if (!isNaN(cur) && !isNaN(max) && max > 0) {
                            const pct = Math.round(100 * cur / max);
                            disp.bright = Object.assign({}, disp.bright, { [ddcReadProc.activeName]: pct });
                        }
                    }
                }
            }
        }

        // Quickshell.screens is the hotplug signal. It is the same list the
        // bar's Variants clones over, so by the time this fires niri has
        // already settled the new output and `niri msg outputs` will describe
        // it correctly.
        Connections {
            target: Quickshell
            function onScreensChanged() {
                disp.refresh();
                brightReadProc.running = true;
                ddcDetectProc.running = true;
            }
        }

        Component.onCompleted: {
            // outputsProc is kicked off by the state file load, not from here:
            // restore() must not run before `saved` is populated.
            brightReadProc.running = true;
            ddcDetectProc.running = true;
        }
    }

    // ---- the bar --------------------------------------------------------
    Variants {
        model: Quickshell.screens

        PanelWindow {
            // Named so a cell nested several levels down can still say which
            // monitor it is drawn on -- see the display cell's onPressed.
            id: bar

            // Variants injects the model element under this name.
            required property var modelData
            screen: modelData

            // Anchoring three edges spans the width; the compositor then
            // reserves the strip so windows do not sit underneath.
            anchors {
                top: true
                left: true
                right: true
            }
            implicitHeight: 32
            color: root.bg

            component Cell: Text {
                color: root.fg
                font.family: root.mono
                font.pixelSize: 13
                anchors.verticalCenter: parent?.verticalCenter ?? undefined
            }

            // An icon plus its value. Two Text items rather than one, because a
            // single Text has a single font.pixelSize and the icons want to be
            // bigger than the digits next to them -- Nerd Font glyphs are drawn
            // to fill a text cell, so at a matched size they read as smaller
            // than the surrounding characters rather than equal to them.
            //
            // Aligned on the baseline, not the centre. The glyphs sit slightly
            // low in their em box, so centring the two items leaves the digits
            // visibly floating above the icon; sharing a baseline puts them on
            // the same line the way they would be in one string.
            //
            // `value` empty is a real state, not a placeholder -- a muted
            // speaker or a disabled radio says everything on its own, and the
            // second Text collapses so no stray gap is left behind.
            // An Item wrapping the Row, rather than being the Row. Three of
            // these cells put a MouseArea inside for click and scroll, and a
            // Row refuses to lay out at all if a child anchors with fill --
            // "Row will not function", and the whole right-hand side collapses.
            // The Item takes the MouseArea, the private Row takes the glyph and
            // the value, and neither interferes with the other.
            component IconCell: Item {
                property string glyph: ""
                property string value: ""
                property color tint: root.fg

                implicitWidth: cellRow.implicitWidth
                implicitHeight: cellRow.implicitHeight
                anchors.verticalCenter: parent?.verticalCenter ?? undefined

                Row {
                    id: cellRow
                    spacing: 5

                    Text {
                        id: cellIcon
                        text: glyph
                        color: tint
                        font.family: root.mono
                        font.pixelSize: 18
                    }
                    Text {
                        text: value
                        visible: text !== ""
                        color: tint
                        font.family: root.mono
                        font.pixelSize: 13
                        // Baseline, not centre. Nerd Font glyphs sit low in
                        // their em box, so centring leaves the digits visibly
                        // floating above the icon; a shared baseline puts them
                        // on the same line the way one string would.
                        anchors.baseline: cellIcon.baseline
                    }
                }
            }

            // ---- centre: clock, click for world clock ----
            Text {
                id: clockText
                anchors.centerIn: parent
                color: root.openPanel === "clock" ? root.accent : root.fg
                font.family: root.mono
                font.pixelSize: 13
                // No seconds, by request. SystemClock ticks at the precision
                // you ask for, so dropping to Minutes is not just cosmetic --
                // it is one repaint a minute instead of one a second.
                text: Qt.formatDateTime(clock.date, "ddd d MMM  HH:mm")

                SystemClock {
                    id: clock
                    precision: SystemClock.Minutes
                }

                MouseArea {
                    anchors.fill: parent
                    // onPressed for the same reason as the wifi cell: an open
                    // wifi picker holds the keyboard, and pressing any bar cell
                    // cancels the pointer grab before onClicked can fire.
                    onPressed: root.openPanel = root.openPanel === "clock" ? "" : "clock"
                }
            }

            // ---- right: status ----
            Row {
                anchors.right: parent.right
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                spacing: 14

                // The labels are icons, but the *values* stay as text. An icon
                // can say "this is the CPU"; it cannot say 43%, and replacing
                // the SSID or the connected-device count with a picture would
                // throw away the only part of the cell worth reading.
                // nf-oct-cpu, not one of the several Material chip glyphs.
                // md-cpu_64_bit and md-memory are both a square die with legs
                // and are indistinguishable at bar size -- they were tried side
                // by side and could not be told apart -- so CPU and RAM would
                // have shown the same picture twice. The Octicon processor and
                // the Material expansion card below are different silhouettes:
                // a square versus a horizontal stick.
                // System page. First in the row, so the three live percentages
                // that follow read as the running state of the machine this
                // cell describes.
                //
                // nf-md-server: three stacked units, solid rather than outlined,
                // so it carries weight next to the thin glyphs around it. Every
                // other candidate collided with something already in this row --
                // a chip with the CPU glyph next to it, an expansion card with
                // the RAM stick, a laptop or a tower with the monitor further
                // along. Stacked racks are the one shape here that is not a
                // picture of a single component.
                IconCell {
                    glyph: root.icon(0xF048B)
                    value: ""
                    tint: root.openPanel === "system" ? root.accent : root.fg

                    MouseArea {
                        anchors.fill: parent
                        // onPressed for the same reason as the wifi cell: an
                        // open picker holds the keyboard, and pressing any bar
                        // cell cancels the pointer grab before onClicked fires.
                        onPressed: root.openPanel = root.openPanel === "system" ? "" : "system"
                    }
                }

                // Each of these hides whole rather than showing a glyph with a
                // placeholder after it. The icon on its own says which reading
                // is missing, which is not something worth taking bar width to
                // say -- and a stat cell with no number reads as a broken
                // probe rather than as one that has not answered yet.
                IconCell {
                    glyph: root.icon(0xF4BC)
                    value: sys.cpuPct.toFixed(0) + "%"
                    visible: sys.cpuPct >= 0
                }
                IconCell {
                    // nf-md-expansion_card_variant -- reads as a RAM stick.
                    glyph: root.icon(0xF0FB2)
                    value: sys.memPct.toFixed(0) + "%"
                    visible: sys.memPct >= 0
                }
                IconCell {
                    // nf-md-harddisk
                    glyph: root.icon(0xF02CA)
                    value: sys.diskPct
                    visible: sys.diskPct !== ""
                }

                // Volume. Scroll to adjust, click to mute, right-click to pick
                // an output device -- roughly the macOS menu-bar behaviour.
                //
                // Glyph only, no percentage: the speaker gains an arc as the
                // level rises, which costs no bar width, where a figure beside
                // it costs three characters and reflows the row as it crosses
                // 100. Muted is its own glyph (the crossed-out speaker) rather
                // than the word, which is the one state worth recognising
                // without reading.
                //
                // The trade is resolution -- four steps rather than a hundred,
                // so the cell says roughly-how-loud rather than exactly. The
                // exact figure is only worth having while dragging, and the
                // panel slider carries it there.
                //
                // No sink at all gets a third glyph rather than the muted one,
                // because the two are not the same thing: muted is a state you
                // chose and can click to undo, no-sink is the audio stack
                // having nothing to play to, where clicking does nothing.
                IconCell {
                    id: volCell
                    readonly property var a: audio.sink?.audio
                    readonly property int vol: a ? Math.round(a.volume * 100) : 0

                    tint: root.openPanel === "audio" ? root.accent : root.fg
                    glyph: {
                        // nf-md-volume_mute -- speaker with a cross beside it.
                        // Checked against the muted glyph at the 18px this
                        // actually renders at: nf-md-volume_variant_off was the
                        // other candidate and draws hairline-thin at that size,
                        // visibly lighter than every other glyph in the row.
                        if (!a)
                            return root.icon(0xF075F);
                        // nf-md-volume_off, then _low / _medium / _high.
                        if (a.muted || vol === 0)
                            return root.icon(0xF0581);
                        return root.icon(vol < 34 ? 0xF057F : vol < 67 ? 0xF0580 : 0xF057E);
                    }
                    MouseArea {
                        anchors.fill: parent
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        // onPressed for the same reason as the wifi cell: an
                        // open wifi picker holds the keyboard, and pressing any
                        // bar cell cancels the pointer grab before onClicked
                        // can fire. Mute is on the same handler so both buttons
                        // behave alike -- a mute that needed two clicks only
                        // while the wifi panel happened to be open would be a
                        // far stranger bug to be told about than this one.
                        onPressed: mouse => {
                            if (mouse.button === Qt.RightButton)
                                root.openPanel = root.openPanel === "audio" ? "" : "audio";
                            else if (audio.sink?.audio)
                                audio.sink.audio.muted = !audio.sink.audio.muted;
                        }
                        onWheel: wheel => audio.bump(wheel.angleDelta.y > 0 ? 0.05 : -0.05)
                    }
                }

                // Wifi: NetworkManager via Quickshell.Networking. Click for
                // the network picker.
                //
                // Connected shows no text. SSIDs are unbounded in length and a
                // long one shoves the whole right-hand row sideways, moving the
                // clock and every cell after it -- the bar visibly reflows when
                // you change networks. The accent tint carries "connected" on
                // its own, and the SSID is one click away in the picker for the
                // rare times it actually matters.
                //
                // No text in any state. The cell used to show "--" for
                // radio-on-but-associated-with-nothing, which is the one state
                // the glyph does not express on its own, but a placeholder
                // sitting in the bar reads as something being broken rather
                // than as nothing being connected. Radio off is the
                // struck-through glyph, and "off" next to a crossed-out wifi
                // icon would say the same thing twice anyway.
                //
                // So connected and on-but-unassociated are now told apart by
                // the tint alone. If that turns out to be too quiet, the fix is
                // a third glyph for unassociated rather than bringing the text
                // back.
                IconCell {
                    // accent means connected, not merely panel-open. The picker
                    // is a large popup on screen when open, so it does not need
                    // the tint to announce itself as well.
                    tint: net.active || root.openPanel === "wifi" ? root.accent : root.fg
                    // nf-md-wifi / nf-md-wifi_off
                    glyph: root.icon(Networking.wifiEnabled ? 0xF05A9 : 0xF05AA)

                    MouseArea {
                        anchors.fill: parent
                        // onPressed, not onClicked, and this is the cell where
                        // the reason lives -- the other three copy it.
                        //
                        // onClicked needs the press and the release to land on
                        // the same item. The wifi picker is the only surface
                        // here that asks for keyboard interactivity
                        // (WlrKeyboardFocus.OnDemand, which its passphrase
                        // field cannot do without), so while it is open it
                        // holds the keyboard. Pressing any bar cell makes the
                        // compositor move focus off it, Qt cancels the
                        // in-flight pointer grab, and onClicked never fires.
                        //
                        // Measured, not guessed: with onClicked the log showed
                        //   09:50:43.554  wifi PRESS  openPanel='wifi'
                        //   09:50:43.557  wifi CANCELED
                        // 3.3ms apart, no release, panel left open -- and the
                        // next press a second later worked. That is the "takes
                        // two clicks to close the wifi panel" report, and it
                        // hits whichever cell you press while wifi is open, not
                        // just this one.
                        //
                        // The press itself is always delivered; only the grab
                        // that follows it is at risk. So toggling on press is
                        // immune to this regardless of what cancels the grab.
                        // The click-away catcher already works this way.
                        onPressed: root.openPanel = root.openPanel === "wifi" ? "" : "wifi"
                    }
                }

                // Bluetooth: bluez via Quickshell.Bluetooth. Click for the
                // device picker.
                //
                // Three glyphs, because the three states are genuinely
                // different and used to be told apart only by reading the word
                // after "BT": no adapter or radio off is the struck-through
                // rune, on-but-idle is the plain rune, and something actually
                // connected is the rune with the link arc.
                //
                // Connected is doubly marked -- link-arc glyph *and* accent
                // tint. That is deliberate: the arc is a small difference at
                // 18px and easy to miss at a glance, while colour reads from
                // across the room. The glyph stays because colour alone cannot
                // separate radio-off from on-but-idle.
                IconCell {
                    readonly property var ad: bt.adapter
                    readonly property int conn: bt.connectedDevices.length

                    // accent means something is connected, matching the wifi
                    // cell above -- one colour, one meaning, across the row.
                    // The picker is a large popup on screen when open, so it
                    // does not need the tint to announce itself as well.
                    tint: conn > 0 || root.openPanel === "bt" ? root.accent : root.fg
                    glyph: {
                        // nf-md-bluetooth_off / _connect / nf-md-bluetooth
                        if (!ad || !ad.enabled)
                            return root.icon(0xF00B2);
                        return root.icon(conn > 0 ? 0xF00B1 : 0xF00AF);
                    }
                    // Icon only. The three glyphs already say everything the
                    // count did -- off, on, on-with-something-connected -- and
                    // the number was only ever 0 or 1 in practice. The panel
                    // still spells out "bluez not running" if the adapter is
                    // missing entirely, which is the one case the glyph alone
                    // cannot distinguish from a radio that is simply off.
                    value: ""

                    MouseArea {
                        anchors.fill: parent
                        // onPressed for the same reason as the wifi cell: an
                        // open wifi picker holds the keyboard, and pressing any
                        // bar cell cancels the pointer grab before onClicked
                        // can fire.
                        onPressed: root.openPanel = root.openPanel === "bt" ? "" : "bt"
                    }
                }

                // Displays. Same shape as the bluetooth cell above: the glyph
                // carries the one bit of state worth seeing at a glance --
                // whether anything is plugged in -- and the panel carries
                // everything else.
                //
                // The cell stays visible with no external monitor attached,
                // because the internal panel's brightness lives in this picker
                // too and is worth reaching without a keyboard.
                IconCell {
                    readonly property int count: disp.list.length

                    tint: count > 1 || root.openPanel === "display" ? root.accent : root.fg
                    // nf-md-television for one, nf-md-monitor_multiple for
                    // several. Two monitors are drawn as two overlapping
                    // screens, which is legible at bar size in a way a "2" next
                    // to one screen would not be.
                    //
                    // television rather than nf-md-monitor for the single case:
                    // monitor hangs its screen on a narrow pedestal stand, which
                    // at 18px reads as an all-in-one computer rather than as a
                    // display. television is the same screen on a flat foot and
                    // stays a screen.
                    //
                    // 0xF0382 was here for the multiple case and is not
                    // monitor_multiple -- it renders as an asterisk. Nothing
                    // caught it because it only appears with two displays
                    // attached. The real codepoint is one past monitor.
                    glyph: root.icon(count > 1 ? 0xF037A : 0xF0502)
                    value: ""

                    MouseArea {
                        anchors.fill: parent
                        // onPressed for the same reason as the wifi cell: an
                        // open wifi picker holds the keyboard, and pressing any
                        // bar cell cancels the pointer grab before onClicked
                        // can fire.
                        onPressed: {
                            // Set before openPanel, so the picker's "which
                            // monitor first" and "which monitor to open on"
                            // bindings are already settled by the time the
                            // window is made visible. Setting it afterwards
                            // would show one frame in the old order.
                            root.activeOutput = bar.modelData.name;
                            root.openPanel = root.openPanel === "display" ? "" : "display";
                            // Cheap and worth doing on every open: niri's view
                            // is authoritative and something outside the shell
                            // -- a config reload, `niri msg` from a terminal --
                            // may have changed it since the last refresh. The
                            // slow probe (ddcutil detect) deliberately does not
                            // run here.
                            if (root.openPanel === "display")
                                disp.refresh();
                        }
                    }
                }

                // Battery. Every fact here comes from the info scope rather
                // than from a second read of upower, so this cell and the
                // system page cannot report different charges -- they used to
                // hold separate copies of the same expression, which is the
                // kind of duplication that only stays correct by luck.
                //
                // Glyph and wording are deliberately identical to the lock
                // screen's --batstr -- see the battext() and battery_status()
                // hunks in nixos/pkgs/swaylock-effects-weekday.patch. The two
                // are read within seconds of each other every time the machine
                // locks, so any disagreement between them reads as a bug in one
                // of them. Change one, change the other.
                //
                // Both halves of that agreement are now pinned: the table is
                // root.batGlyph and the percentage indexing it is info.batPct,
                // which reads the patch's own two sysfs files. Taking upower's
                // percentage instead left the bar two points under the lock
                // screen, which is enough to show a different number of bars.
                IconCell {
                    readonly property bool present: info.batPresent
                    // "Full" counts as charging, matching the patch, which
                    // treats a status of Charging or Full the same way. On the
                    // bolt there is no level to draw anyway.
                    readonly property bool charging: present
                        && (info.bat.state === UPowerDeviceState.Charging
                            || info.bat.state === UPowerDeviceState.FullyCharged)
                    readonly property int pct: present ? info.batPct : 0

                    glyph: present ? root.batGlyph(pct, charging) : ""

                    // Colour is bar-only: swaylock draws the whole battery line
                    // in --text-color and has no per-line colour option, so the
                    // lock screen shows the same glyph in the same grey. The
                    // thresholds still line up with the icon, so an empty cell
                    // is always red and a one-bar cell is always peach.
                    //
                    // Goes caution yellow while the machine is being held awake.
                    // Staying awake is a thing being done to the battery, so
                    // this is not a category error -- and it is the cell the
                    // eye already goes to.
                    //
                    // Precedence, in a single colour channel carrying two
                    // different kinds of fact:
                    //
                    //   <10% discharging  red     emergency, wins outright
                    //   held awake        yellow
                    //   <20% discharging  peach
                    //   otherwise         fg
                    //
                    // Yellow beats the sub-20% peach because the glyph shape
                    // and the "17%" beside it already say the charge is low --
                    // colour is the redundant channel there, and the only
                    // channel the mode has at all.
                    //
                    // Under 10% it loses, and that is a real blind spot rather
                    // than a clean win: held awake at 8% the cell reads red and
                    // says nothing about the mode, which is the charge level
                    // where being pinned awake matters most. It is accepted
                    // because at that point the action is the same either way
                    // -- plug in -- and red is the colour that says so
                    // loudest. The panel still reports the mode. A second cell
                    // would show both at once and was tried; it was not wanted
                    // on the bar, so this is the deliberate trade.
                    //
                    // charging suppresses red and peach as it always has -- a
                    // battery at 6% with the charger in is recovering, not
                    // dying -- but not the yellow, which is true regardless of
                    // what the charger is doing.
                    //
                    // This is still the one cell that does not go accent while
                    // its own panel is open, which every other cell does.
                    // Lighting it on open would be a third meaning for a colour
                    // already carrying two.
                    tint: {
                        if (present && !charging && pct < 10)
                            return root.bad;
                        if (awake.running)
                            return root.caution;
                        if (present && !charging && pct < 20)
                            return root.warn;
                        return root.fg;
                    }

                    // "󰂁 63%" -- the lock screen's format string is
                    // "{icon} {p}%", which expands to exactly this.
                    value: present ? pct + "%" : ""

                    MouseArea {
                        anchors.fill: parent
                        // onPressed for the same reason as the wifi cell: an
                        // open wifi picker holds the keyboard, and pressing any
                        // bar cell cancels the pointer grab before onClicked
                        // can fire.
                        onPressed: root.openPanel = root.openPanel === "battery" ? "" : "battery"
                    }
                }
            }
        }
    }

    // ---- popups ---------------------------------------------------------
    // Separate layer-shell surfaces rather than PopupWindow: the bar is only
    // 32px tall, so anything drawn inside it would be clipped. ExclusionMode
    // Ignore keeps them from reserving screen space of their own.

    // Full-width strip that highlights under the cursor. Left click activates,
    // right click is the destructive variant (forget network / unpair).
    component PickerRow: Rectangle {
        id: pickerRow
        signal activated
        signal secondaryActivated

        height: 26
        color: rowMouse.containsMouse ? root.hover : "transparent"

        MouseArea {
            id: rowMouse
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onClicked: mouse => mouse.button === Qt.RightButton ? pickerRow.secondaryActivated() : pickerRow.activated()
        }
    }

    component PickerHeading: Text {
        color: root.dim
        font.family: root.mono
        font.pixelSize: 11
        leftPadding: root.inset
    }

    // A label and its value on one line, for pages that are read rather than
    // clicked. The label column is a fixed width so the values line up down the
    // page; the value elides instead of wrapping, because each one is a single
    // identifier and a truncated identifier is easier to scan past than one
    // broken across two lines.
    component InfoRow: Row {
        id: infoRow
        property string label
        property string value
        // 92 suits the 530px system page. The wifi picker is 380 and its
        // labels are one word, so it passes something narrower rather than
        // spending a quarter of the panel on whitespace.
        property int labelWidth: 92

        height: 18
        leftPadding: root.inset

        Text {
            width: infoRow.labelWidth
            text: infoRow.label
            color: root.dim
            font.family: root.mono
            font.pixelSize: 12
        }

        // Minus the padding as well as the label column: Row starts its
        // children at leftPadding but does not shrink the width it was given,
        // so without this the value would elide against a right edge one inset
        // past the panel.
        Text {
            width: infoRow.width - infoRow.labelWidth - infoRow.leftPadding
            text: infoRow.value
            elide: Text.ElideRight
            color: root.fg
            font.family: root.mono
            font.pixelSize: 12
        }
    }

    // A chip in a segmented row -- scale factors, brightness steps. Used where
    // the choices are few, short and mutually exclusive, which a column of
    // full-width PickerRows would waste a lot of panel height saying.
    //
    // Deliberately not a drag slider. Brightness on an external monitor goes
    // out over DDC/CI, where a single write costs 100-300ms; a slider would
    // queue a write per pixel of travel and spend the next ten seconds
    // replaying them into a monitor that fell further behind with each one.
    // Discrete steps are one write per click.
    component SegCell: Rectangle {
        id: seg
        property string label
        property bool active: false
        property bool available: true
        // Overridable so a chip that selects something the machine should not
        // be left in can say so in its own colour. Defaults to accent, which is
        // what every ordinary "this one is selected" chip wants.
        property color activeColor: root.accent
        signal activated

        width: segText.implicitWidth + 14
        height: 22
        radius: 3
        color: seg.active ? seg.activeColor : (segMouse.containsMouse && seg.available ? root.hover : "transparent")
        border.width: 1
        border.color: seg.active ? seg.activeColor : root.hover

        Text {
            id: segText
            anchors.centerIn: parent
            text: seg.label
            // On the accent fill the text has to flip to the background colour
            // -- fg on accent is two light colours on top of each other.
            color: seg.active ? root.bg : (seg.available ? root.fg : root.dim)
            font.family: root.mono
            font.pixelSize: 11
        }

        MouseArea {
            id: segMouse
            anchors.fill: parent
            hoverEnabled: true
            // onPressed for the same reason as the bar cells: a picker holding
            // keyboard focus cancels the pointer grab before onClicked fires.
            onPressed: if (seg.available) seg.activated()
        }
    }

    // Click-away catcher. A transparent full-screen surface that closes
    // whichever picker is open when a click lands outside it.
    //
    // On WlrLayer.Top while the pickers are on Overlay, which is what keeps it
    // underneath them. Layer-shell orders its four layers strictly
    // (Background < Bottom < Top < Overlay), so this is guaranteed by the
    // protocol and needs no cooperation from the compositor.
    //
    // It used to sit on Overlay too, with the pickers, resting on the theory
    // that "surfaces within one layer stack in the order the compositor learns
    // about them, and Quickshell creates them in declaration order, so
    // declaring the catcher first puts it underneath". That does not hold.
    // This catcher and a picker both become visible from the same
    // root.openPanel change, so both surfaces get mapped in one pass with
    // nothing ordering them against each other -- and in practice the catcher
    // came out on top. It then swallowed every press aimed at a picker, so
    // clicking a network or a device closed the panel instead of selecting
    // anything: the pickers were entirely unclickable. Declaration order is
    // not a stacking guarantee; layer assignment is.
    //
    // Top still sits above ordinary toplevel windows, so it catches clicks
    // anywhere on the desktop, which is the whole job.
    //
    // Starts below the bar rather than covering it. The bar is on Top as well,
    // but the two never overlap -- the bar is the first 32px and this begins
    // at 32 -- so sharing a layer with it introduces no ambiguity of its own.
    // Covering it would swallow clicks on the very cells that switch between
    // pickers: clicking wifi while bluetooth is open has to reach the wifi
    // cell, which sets openPanel to "wifi" and swaps them in one click. Left
    // uncovered, that keeps working untouched.
    //
    // keyboardFocus None so the surface never takes focus from the window
    // underneath; it only exists to catch a pointer press.
    PanelWindow {
        visible: root.openPanel !== ""
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }
        // The bar is 32 tall; the pickers hang from 34.
        margins.top: 32

        MouseArea {
            anchors.fill: parent
            // Any button, so a stray right- or middle-click dismisses too
            // rather than being silently eaten by a surface the user cannot
            // see.
            acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
            onPressed: root.openPanel = ""
        }
    }

    // Audio: volume, then the output and input device pickers.
    PanelWindow {
        visible: root.openPanel === "audio"
        WlrLayershell.layer: WlrLayer.Overlay
        exclusionMode: ExclusionMode.Ignore
        anchors {
            top: true
            right: true
        }
        margins {
            top: 34
            right: 8
        }
        implicitWidth: 340
        implicitHeight: audioCol.implicitHeight + 20
        color: root.bg

        Column {
            id: audioCol
            anchors.fill: parent
            anchors.margins: 10
            spacing: 6

            // Volume, above the device list because it is what this panel gets
            // opened for most of the time -- switching output device is the
            // rarer errand, and a control you reach for daily should not sit
            // under a list whose length depends on what is plugged in.
            //
            // Same vocabulary as the bar cell: the same four speaker glyphs,
            // gaining an arc as the level rises, the crossed-out one for muted.
            //
            // The percentage lives here rather than on the bar, which is the
            // whole split -- the bar is glanced at and pays for every character
            // in width, the panel is looked at deliberately and has room. This
            // is also the only place the exact figure is worth having, because
            // it is the only place you can drag to a particular one.
            //
            // With no sink the speaker goes red rather than dim. Dim is the
            // colour this file uses for "not applicable right now"; nothing to
            // play to is a fault, and the one state here worth recognising
            // without reading the device list underneath.
            PickerHeading {
                text: "Volume"
            }

            Item {
                id: volSlider
                readonly property var a: audio.sink?.audio
                // Muted keeps its position and dims rather than collapsing to
                // zero, so the row still says what unmuting will return to.
                // The dim carries "not audible right now", and the slashed
                // glyph says it outright -- collapsing as well would cost the
                // position and force the figure to read 0% beside a speaker
                // you can click back to 40.
                readonly property real level: a ? Math.max(0, Math.min(1, a.volume)) : 0

                // Where the comfort notch sits. See the note on the notch
                // itself before moving it: this is a perceptual scale, so the
                // number means something, but not the thing the same number
                // means in hearing-safety guidance.
                readonly property real comfort: 0.8

                width: audioCol.width
                height: 26

                Text {
                    id: volIcon
                    anchors.left: parent.left
                    anchors.leftMargin: root.inset
                    anchors.verticalCenter: parent.verticalCenter
                    // Fixed width, centred, because these five glyphs are not
                    // all the same width -- the slashed and crossed speakers
                    // are wider than the plain one. The track anchors to this
                    // Text's right edge, so sizing it to its content would jump
                    // the track's left end sideways every time the level
                    // crossed a glyph threshold: during a drag, the control
                    // wobbling under the cursor.
                    width: 22
                    horizontalAlignment: Text.AlignHCenter
                    font.family: root.mono
                    font.pixelSize: 18
                    color: !volSlider.a ? root.bad : volSlider.a.muted ? root.dim : root.fg
                    text: {
                        const a = volSlider.a;
                        // Codepoints already verified against this font at this
                        // size for the bar cell -- see the note there before
                        // swapping any of them.
                        if (!a)
                            return root.icon(0xF075F);
                        if (a.muted || volSlider.level === 0)
                            return root.icon(0xF0581);
                        const v = volSlider.level * 100;
                        return root.icon(v < 34 ? 0xF057F : v < 67 ? 0xF0580 : 0xF057E);
                    }

                    // Click the speaker to mute, matching the bar cell's left
                    // click. The track does not mute -- a stray click there
                    // should set a level, not silence the machine.
                    MouseArea {
                        anchors.fill: parent
                        enabled: !!volSlider.a
                        onPressed: volSlider.a.muted = !volSlider.a.muted
                    }
                }

                // The track is 4px but the grab area is the full row height.
                // A 4px drag target is a control you have to aim at.
                Rectangle {
                    id: volTrack
                    anchors.left: volIcon.right
                    anchors.leftMargin: 10
                    anchors.right: volPct.left
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    height: 4
                    radius: 2
                    color: root.hover

                    // Accent or, muted, dim -- never bad. With no sink the level
                    // is 0 and this has no width to colour, so a red branch
                    // here would be a line that reads as handling the fault
                    // while doing nothing. The red speaker carries that state.
                    Rectangle {
                        width: volTrack.width * volSlider.level
                        height: parent.height
                        radius: parent.radius
                        color: volSlider.a && volSlider.a.muted ? root.dim : root.accent
                    }

                    // Comfort notch. Drawn in the panel background so it reads
                    // as a gap cut out of the bar, which works the same whether
                    // the fill has reached it or not -- and stays quiet, which
                    // is what a reference mark should be. Above the fill in
                    // document order so it is not painted over.
                    //
                    // 80% is a real point on this scale and not an arbitrary
                    // one: pipewire's channelVolumes are the cube of the value
                    // shown here (measured -- 0.25 here is 0.015625 there), so
                    // this slider is perceptual, and the notch sits about 5.8dB
                    // below full rather than the ~2dB it would mean on a linear
                    // control.
                    //
                    // It is still a comfort mark, not a safety one. Hearing
                    // guidance is in dB SPL over time and depends on what is
                    // plugged in: this notch is conservative on the internal
                    // speakers and optimistic on sensitive headphones, because
                    // slider position says nothing about either.
                    Rectangle {
                        x: volTrack.width * volSlider.comfort - width / 2
                        anchors.verticalCenter: parent.verticalCenter
                        width: 2
                        height: 8
                        color: root.bg
                    }
                }

                // Fixed width and right-aligned so the track's right-hand end
                // does not move between "9%" and "100%" -- the same jitter the
                // glyph column had on the left.
                Text {
                    id: volPct
                    anchors.right: parent.right
                    anchors.rightMargin: root.inset
                    anchors.verticalCenter: parent.verticalCenter
                    width: 30
                    horizontalAlignment: Text.AlignRight
                    font.family: root.mono
                    font.pixelSize: 11
                    color: !volSlider.a ? root.bad : volSlider.a.muted ? root.dim : root.fg
                    // Nothing to report with no sink -- the red speaker on the
                    // left is the whole message, and a percentage of nothing
                    // beside it would just be 0%.
                    text: volSlider.a ? Math.round(volSlider.level * 100) + "%" : ""
                }

                MouseArea {
                    anchors.left: volTrack.left
                    anchors.right: volTrack.right
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    enabled: !!volSlider.a
                    // Set on press and keep setting while held, so a click
                    // jumps and a drag scrubs without needing two code paths.
                    // No pressed-check in onPositionChanged: a MouseArea only
                    // reports motion while a button is down unless hoverEnabled
                    // is set, and it is not.
                    onPressed: mouse => audio.setLevel(mouse.x / width)
                    onPositionChanged: mouse => audio.setLevel(mouse.x / width)
                    onWheel: wheel => audio.bump(wheel.angleDelta.y > 0 ? 0.05 : -0.05)
                }
            }

            PickerHeading {
                text: "Output device"
            }

            Repeater {
                model: audio.sinks

                PickerRow {
                    id: sinkRow
                    required property var modelData
                    readonly property bool isCurrent: modelData === audio.sink
                    width: audioCol.width
                    // preferredDefaultAudioSink is the writable knob;
                    // defaultAudioSink itself is read-only and follows it.
                    onActivated: {
                        Pipewire.preferredDefaultAudioSink = sinkRow.modelData;
                        root.openPanel = "";
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        anchors.leftMargin: root.inset
                        width: parent.width - 12
                        elide: Text.ElideRight
                        color: sinkRow.isCurrent ? root.accent : root.fg
                        font.family: root.mono
                        font.pixelSize: 12
                        text: (sinkRow.isCurrent ? "* " : "  ") + (sinkRow.modelData.description || sinkRow.modelData.nickname || sinkRow.modelData.name)
                    }
                }
            }

            // Which device the machine records from. Nothing on the bar says
            // this -- the volume cell is about playback -- so before this list
            // the only way to find out was wpctl or pavucontrol.
            //
            // Worth surfacing because the answer changes under you: plugging in
            // a USB sound card moves the default capture device as well as the
            // default output, which is easy to miss when you were only thinking
            // about playback.
            PickerHeading {
                text: "Input device"
                visible: audio.sources.length > 0
            }

            Repeater {
                model: audio.sources

                PickerRow {
                    id: srcRow
                    required property var modelData
                    readonly property bool isCurrent: modelData === audio.source
                    width: audioCol.width
                    // Mirrors the sink side: preferredDefaultAudioSource is the
                    // writable knob, defaultAudioSource follows it.
                    //
                    // This changes what *new* streams open by default. An app
                    // already recording keeps the device it opened with, and
                    // has to be moved per-stream in pavucontrol's Recording tab
                    // or restarted -- pipewire routes existing streams, and
                    // nothing here reaches into them.
                    onActivated: {
                        Pipewire.preferredDefaultAudioSource = srcRow.modelData;
                        root.openPanel = "";
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        anchors.leftMargin: root.inset
                        width: parent.width - 12
                        elide: Text.ElideRight
                        color: srcRow.isCurrent ? root.accent : root.fg
                        font.family: root.mono
                        font.pixelSize: 12
                        text: (srcRow.isCurrent ? "* " : "  ") + (srcRow.modelData.description || srcRow.modelData.nickname || srcRow.modelData.name)
                    }
                }
            }

            PickerRow {
                width: audioCol.width
                onActivated: {
                    mixerProc.running = true;
                    root.openPanel = "";
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.leftMargin: root.inset
                    color: root.dim
                    font.family: root.mono
                    font.pixelSize: 12
                    // No leading pad. The device rows above spend two columns
                    // on a "* " marker; this is an action rather than a thing
                    // that can be current, so it has no marker to leave room
                    // for and lines up with the headings instead.
                    text: "Open pavucontrol (per-app mixer)..."
                }
            }
        }

        Process {
            id: mixerProc
            command: ["pavucontrol"]
        }
    }

    // Wifi picker.
    PanelWindow {
        id: wifiPanel
        visible: root.openPanel === "wifi"
        WlrLayershell.layer: WlrLayer.Overlay
        // Required for the passphrase field: a layer surface receives no key
        // events at all unless it asks for keyboard interactivity. OnDemand
        // rather than Exclusive so the popup only holds the keyboard while it
        // is clicked into, and typing goes back to the focused window after.
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
        exclusionMode: ExclusionMode.Ignore
        anchors {
            top: true
            right: true
        }
        margins {
            top: 34
            right: 8
        }
        implicitWidth: 380
        implicitHeight: wifiCol.implicitHeight + 20
        color: root.bg

        // Reset transient state when the picker is dismissed, so a stale
        // password prompt or error is not waiting on the next open.
        onVisibleChanged: {
            if (!visible) {
                net.pskTarget = null;
                net.error = "";
                pskField.text = "";
            }
        }

        Column {
            id: wifiCol
            anchors.fill: parent
            anchors.margins: 10
            spacing: 6

            // Radio toggle. wifiHardwareEnabled is the rfkill hard switch: if
            // that is off, software cannot turn the radio back on and the
            // toggle would silently do nothing, so say so instead.
            PickerRow {
                width: wifiCol.width
                height: 22
                onActivated: {
                    if (Networking.wifiHardwareEnabled)
                        Networking.wifiEnabled = !Networking.wifiEnabled;
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.leftMargin: root.inset
                    color: root.dim
                    font.family: root.mono
                    font.pixelSize: 11
                    text: "Wi-Fi"
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.right: parent.right
                    anchors.rightMargin: root.inset
                    color: !Networking.wifiHardwareEnabled ? root.bad : Networking.wifiEnabled ? root.accent : root.dim
                    font.family: root.mono
                    font.pixelSize: 11
                    text: !Networking.wifiHardwareEnabled ? "Blocked by hardware switch" : Networking.wifiEnabled ? "On" : "Off"
                }
            }

            // Everything about the connection you already have, above the list
            // of ones you do not. The list is the long, scrolling, variable
            // part of this panel; putting the current addresses and the DNS
            // override underneath it means scrolling past the answer to reach
            // it, and on a busy network the answer is off the bottom entirely.
            //
            // The DNS chips are the manual half of the story. The automatic
            // half is services.resolved in configuration.nix, which is what
            // makes the nameserver follow the network by itself. These are for
            // when the network's own resolver is present and reachable but not
            // one you want to use -- a captive portal, a hotel, an office that
            // blackholes half the internet.
            Column {
                id: connCol
                width: wifiCol.width
                spacing: 4

                // Either source is enough. net.active comes from the
                // Quickshell.Networking D-Bus binding, which is instant but
                // goes stale if NetworkManager restarts under a running shell
                // -- a `nixos-rebuild switch` does exactly that, and the
                // binding does not reconnect, so devices silently empties and
                // the whole panel reads as "not connected" until the shell is
                // restarted. localAddr comes from nmcli in a subprocess, which
                // cannot go stale that way but takes a moment to arrive.
                //
                // Requiring both would mean this block vanishes on a stale
                // binding, taking the DNS controls with it -- precisely when
                // something is wrong with the network and they are wanted.
                visible: net.active !== null || net.localAddr !== ""

                // 56 rather than the 92 the system page uses -- see InfoRow.
                InfoRow {
                    width: connCol.width
                    labelWidth: 56
                    label: "Local"
                    value: net.localAddr
                    // An empty row says "no address yet" more honestly than a
                    // placeholder does, and takes up no height saying it.
                    visible: net.localAddr !== ""
                }

                InfoRow {
                    width: connCol.width
                    labelWidth: 56
                    label: "Public"
                    // Blank means the last fetch failed, which on a connection
                    // that is otherwise up almost always means DNS. Say that
                    // rather than leaving an empty row that reads as "still
                    // loading" forever.
                    value: net.publicAddr !== "" ? net.publicAddr
                        : (net.dnsResolving ? "checking..." : "unavailable")
                }

                PickerHeading { text: "DNS" }

                Row {
                    leftPadding: root.inset
                    spacing: 4

                    SegCell {
                        label: "DHCP"
                        active: net.dnsMode === "dhcp"
                        available: !net.dnsBusy
                        onActivated: net.dnsApply("dhcp")
                    }

                    SegCell {
                        label: "Google"
                        active: net.dnsMode === "google"
                        available: !net.dnsBusy
                        onActivated: net.dnsApply("google")
                    }

                    SegCell {
                        label: "Cloudflare"
                        active: net.dnsMode === "cloudflare"
                        available: !net.dnsBusy
                        onActivated: net.dnsApply("cloudflare")
                    }

                    SegCell {
                        label: "Custom"
                        active: net.dnsMode === "custom"
                        available: !net.dnsBusy
                        // Reveals the field instead of applying: there is
                        // nothing to apply until something has been typed, and
                        // applying an empty Custom would just be DHCP wearing
                        // a different hat.
                        onActivated: {
                            net.dnsMode = "custom";
                            dnsField.forceActiveFocus();
                        }
                    }
                }

                Rectangle {
                    width: parent.width
                    height: 26
                    visible: net.dnsMode === "custom"
                    color: root.hover
                    border.color: dnsField.activeFocus ? root.accent : "transparent"

                    TextInput {
                        id: dnsField
                        anchors.fill: parent
                        anchors.margins: 6
                        verticalAlignment: TextInput.AlignVCenter
                        color: root.fg
                        font.family: root.mono
                        font.pixelSize: 12
                        selectByMouse: true
                        text: net.dnsCustom
                        // textEdited, not textChanged: this fires only for
                        // typing, so the binding above can still push a value
                        // in from the read-back without the two fighting.
                        onTextEdited: net.dnsCustom = text
                        onAccepted: net.dnsApply("custom")
                    }
                }

                // The detect half: what is actually resolving, as opposed to
                // what is configured. "connected, nameserver set, nothing
                // resolves" is a state worth being able to see at a glance
                // rather than deduce from a browser error.
                Text {
                    width: parent.width
                    leftPadding: root.inset
                    rightPadding: root.inset
                    wrapMode: Text.Wrap
                    color: net.dnsResolving ? root.dim : root.bad
                    font.family: root.mono
                    font.pixelSize: 11
                    text: {
                        if (net.dnsMode === "custom" && net.dnsCustom === "")
                            return "Addresses separated by space or comma, Enter to apply";
                        const via = net.dnsEffective !== "" ? net.dnsEffective : "unknown";
                        return via + (net.dnsResolving ? " -- resolving" : " -- not resolving");
                    }
                }
            }

            Repeater {
                model: net.list

                PickerRow {
                    id: netRow
                    required property var modelData
                    width: wifiCol.width
                    onActivated: net.activate(netRow.modelData)
                    // Right-click drops a saved network, the way "Forget This
                    // Network" does on macOS.
                    onSecondaryActivated: {
                        if (netRow.modelData.known)
                            netRow.modelData.forget();
                    }

                    // Each Network emits its own failure. NoSecrets means the
                    // stored passphrase was wrong or missing, so re-prompt
                    // rather than printing an error the user cannot act on.
                    Connections {
                        target: netRow.modelData
                        function onConnectionFailed(reason) {
                            net.error = netRow.modelData.name + ": " + ConnectionFailReason.toString(reason);
                            if (reason === ConnectionFailReason.NoSecrets)
                                net.pskTarget = netRow.modelData;
                        }
                    }

                    Text {
                        id: sigText
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        anchors.leftMargin: root.inset
                        color: netRow.modelData.connected ? root.accent : root.dim
                        font.family: root.mono
                        font.pixelSize: 12
                        text: root.bars(netRow.modelData.signalStrength)
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: sigText.right
                        anchors.leftMargin: 8
                        anchors.right: wifiState.left
                        anchors.rightMargin: 8
                        elide: Text.ElideRight
                        color: netRow.modelData.connected ? root.accent : root.fg
                        font.family: root.mono
                        font.pixelSize: 12
                        text: netRow.modelData.name
                    }

                    Text {
                        id: wifiState
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.right: parent.right
                        anchors.rightMargin: root.inset
                        color: root.dim
                        font.family: root.mono
                        font.pixelSize: 11
                        text: {
                            const n = netRow.modelData;
                            if (n.stateChanging)
                                return root.cap(ConnectionState.toString(n.state)) + "...";
                            if (n.connected)
                                return "Connected";
                            if (n.known)
                                return "Saved";
                            return n.security === WifiSecurityType.Open ? "Open" : "Locked";
                        }
                    }
                }
            }

            // Passphrase prompt. Plain TextInput rather than QtQuick.Controls
            // TextField, to avoid pulling the Controls style stack into the
            // shell for one widget.
            Column {
                id: pskCol
                width: wifiCol.width
                spacing: 4
                visible: net.pskTarget !== null

                property bool showPsk: false

                // One exit for both ways out of the prompt, so the reveal flag
                // and the buffered passphrase can never drift apart. Clearing
                // the text but not the flag is how the *next* network's prompt
                // would open already unmasked, in whatever room the laptop
                // happens to be open in.
                function clear() {
                    net.pskTarget = null;
                    pskField.text = "";
                    showPsk = false;
                }

                PickerHeading {
                    text: net.pskTarget ? "Password for " + net.pskTarget.name : ""
                }

                Rectangle {
                    width: parent.width
                    height: 26
                    color: root.hover
                    border.color: pskField.activeFocus ? root.accent : "transparent"

                    TextInput {
                        id: pskField
                        anchors.fill: parent
                        anchors.margins: 6
                        verticalAlignment: TextInput.AlignVCenter
                        color: root.fg
                        font.family: root.mono
                        font.pixelSize: 12
                        echoMode: pskCol.showPsk ? TextInput.Normal : TextInput.Password
                        selectByMouse: true
                        // Grab focus as soon as the prompt appears, so the
                        // passphrase can be typed without a second click.
                        onVisibleChanged: {
                            if (visible)
                                forceActiveFocus();
                        }
                        onAccepted: {
                            if (net.pskTarget && text.length > 0) {
                                net.pskTarget.connectWithPsk(text);
                                pskCol.clear();
                            }
                        }
                        Keys.onEscapePressed: pskCol.clear()
                    }
                }

                // Show-password toggle. Wrapped in an Item because the
                // MouseArea has to cover the box and its label together: a
                // MouseArea declared directly inside the Row would be laid out
                // as a third column beside them rather than sitting on top.
                Item {
                    width: pskToggle.implicitWidth
                    height: pskToggle.implicitHeight

                    Row {
                        id: pskToggle
                        spacing: 6

                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 13
                            height: 13
                            radius: 2
                            color: pskCol.showPsk ? root.accent : "transparent"
                            border.width: 1
                            border.color: pskCol.showPsk ? root.accent : root.dim

                            Text {
                                anchors.centerIn: parent
                                visible: pskCol.showPsk
                                // nf-md-check_bold, not nf-md-check: the plain
                                // one is a hairline that vanishes at this size
                                // against the accent fill.
                                text: root.icon(0xF0E1E)
                                color: root.bg
                                font.family: root.mono
                                font.pixelSize: 10
                            }
                        }

                        PickerHeading {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Show password"
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: pskCol.showPsk = !pskCol.showPsk
                    }
                }

                PickerHeading {
                    text: "Enter to connect, Esc to cancel"
                }
            }

            Text {
                width: wifiCol.width
                leftPadding: root.inset
                rightPadding: root.inset
                visible: net.error !== ""
                wrapMode: Text.Wrap
                color: root.bad
                font.family: root.mono
                font.pixelSize: 11
                text: net.error
            }

            PickerRow {
                width: wifiCol.width
                onActivated: {
                    netManagerProc.running = true;
                    root.openPanel = "";
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.leftMargin: root.inset
                    color: root.dim
                    font.family: root.mono
                    font.pixelSize: 12
                    // No leading indent, unlike the other launcher rows: this
                    // sits flush with the signal meter in the network rows
                    // above. Same leftMargin and same 12px mono as sigText, so
                    // the "O" lands exactly on the first bar glyph.
                    text: "Open nmtui (hidden SSIDs, static IP, VPN)..."
                }
            }

            PickerHeading {
                width: wifiCol.width
                wrapMode: Text.Wrap
                text: net.dev
                    ? "Scanning on " + net.dev.name
                        + (net.weak > 0 ? " -- " + net.weak + " below 3 bars hidden" : "")
                        + " -- right-click a saved network to forget it"
                    : "Waiting for NetworkManager..."
            }
        }

        Process {
            id: netManagerProc
            // The wifi counterpart to the bluetui row in the bluetooth picker:
            // everything the picker above does not cover -- hidden SSIDs, static
            // addressing, 802.1X, editing a saved connection rather than just
            // forgetting it.
            //
            // nmtui rather than a GUI because there is no good GUI to pick. The
            // two genuinely nice ones, iwgtk and impala, both talk to iwd, and
            // NetworkManager here is on its default wpa_supplicant backend.
            // Switching it is not worth doing on this machine: wlp2s0 is
            // brcmfmac, a fullmac driver that leaves scanning and roaming to
            // Broadcom firmware, which is exactly the arrangement iwd expects to
            // drive itself. That leaves nm-connection-editor, which is uglier
            // than the thing it would replace, or gnome-control-center, which
            // means GNOME. nmtui ships with NetworkManager, is already on PATH,
            // and inherits the terminal palette.
            //
            // kitty and --class for the same reasons as btManagerProc below.
            command: ["kitty", "--class", "nmtui", "-e", "nmtui"]
        }
    }

    // Bluetooth picker.
    PanelWindow {
        visible: root.openPanel === "bt"
        WlrLayershell.layer: WlrLayer.Overlay
        exclusionMode: ExclusionMode.Ignore
        anchors {
            top: true
            right: true
        }
        margins {
            top: 34
            right: 8
        }
        implicitWidth: 380
        implicitHeight: btCol.implicitHeight + 20
        color: root.bg

        // Stop discovery when the picker closes; it keeps the radio awake and
        // leaves the adapter advertising to everyone in range.
        onVisibleChanged: {
            if (!visible)
                bt.scanning = false;
        }

        Column {
            id: btCol
            anchors.fill: parent
            anchors.margins: 10
            spacing: 6

            PickerRow {
                width: btCol.width
                height: 22
                onActivated: {
                    if (bt.adapter)
                        bt.adapter.enabled = !bt.adapter.enabled;
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.leftMargin: root.inset
                    color: root.dim
                    font.family: root.mono
                    font.pixelSize: 11
                    text: "Bluetooth"
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.right: parent.right
                    anchors.rightMargin: root.inset
                    color: !bt.adapter ? root.bad : bt.adapter.enabled ? root.accent : root.dim
                    font.family: root.mono
                    font.pixelSize: 11
                    // No adapter at all means bluez is not on the bus, which is
                    // a different problem from the adapter being powered down.
                    text: !bt.adapter ? "BlueZ not running" : bt.adapter.enabled ? "On" : "Off"
                }
            }

            Repeater {
                model: bt.list

                PickerRow {
                    id: btRow
                    required property var modelData
                    width: btCol.width
                    onActivated: bt.activate(btRow.modelData)
                    onSecondaryActivated: {
                        if (btRow.modelData.paired)
                            btRow.modelData.forget();
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        anchors.leftMargin: root.inset
                        anchors.right: btState.left
                        anchors.rightMargin: 8
                        elide: Text.ElideRight
                        color: btRow.modelData.connected ? root.accent : root.fg
                        font.family: root.mono
                        font.pixelSize: 12
                        // No "* " / "  " prefix. It used to mark the connected
                        // device, but it also pushed every name two characters
                        // right of the "Bluetooth" heading above. The marker was
                        // the third thing saying the same word anyway -- the row
                        // is already tinted with root.accent and btState to the
                        // right already reads "Connected" -- so dropping it
                        // costs nothing and lets the names sit flush.
                        text: btRow.modelData.name
                    }

                    Text {
                        id: btState
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.right: parent.right
                        anchors.rightMargin: root.inset
                        color: root.dim
                        font.family: root.mono
                        font.pixelSize: 11
                        text: {
                            const d = btRow.modelData;
                            if (d.pairing)
                                return "Pairing...";
                            if (d.state === BluetoothDeviceState.Connecting)
                                return "Connecting...";
                            if (d.state === BluetoothDeviceState.Disconnecting)
                                return "Disconnecting...";
                            // batteryAvailable needs bluez's experimental
                            // features, which configuration.nix turns on --
                            // most headsets report charge over that interface.
                            if (d.connected && d.batteryAvailable)
                                return "Connected  " + Math.round(d.battery * 100) + "%";
                            if (d.connected)
                                return "Connected";
                            return d.paired ? "Paired" : "New";
                        }
                    }
                }
            }

            PickerRow {
                width: btCol.width
                height: 22
                onActivated: bt.scanning = !bt.scanning

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.leftMargin: root.inset
                    color: bt.scanning ? root.accent : root.dim
                    font.family: root.mono
                    font.pixelSize: 11
                    text: bt.scanning ? "Scanning for devices... (click to stop)" : "Scan for new devices"
                }

                // The beacons are hidden, not silently dropped. Without a count
                // here a scan that turns up nothing looks like a dead radio,
                // when in fact it found fifty devices and none of them were
                // willing to say what they were.
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.right: parent.right
                    anchors.rightMargin: root.inset
                    visible: bt.hidden > 0
                    color: root.dim
                    font.family: root.mono
                    font.pixelSize: 11
                    text: bt.hidden + " unnamed"
                }
            }

            PickerRow {
                width: btCol.width
                onActivated: {
                    btManagerProc.running = true;
                    root.openPanel = "";
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.leftMargin: root.inset
                    color: root.dim
                    font.family: root.mono
                    font.pixelSize: 12
                    // Flush, like the nmtui row in the wifi picker: the whole
                    // bluetooth column now starts on one left edge -- heading,
                    // device names, scan row and this.
                    text: "Open bluetui (profiles, codecs, pairing)..."
                }
            }

            PickerHeading {
                width: btCol.width
                wrapMode: Text.Wrap
                text: "Put the earphones in pairing mode, hit Scan, then click them. Right-click a paired device to forget it."
            }
        }

        Process {
            id: btManagerProc
            // This used to be blueman-manager. bluetui is the escape hatch now:
            // it is a terminal app, so it inherits the palette instead of
            // fighting it, and unlike Quickshell it registers a bluez pairing
            // agent of its own (org.bluez.Agent1 / RegisterAgent /
            // RequestDefaultAgent are all in the binary), so a pairing started
            // from inside it prompts inside it.
            //
            // Being a TUI it needs a terminal to live in. kitty rather than
            // foot, matching nautilus-open-any-terminal in configuration.nix;
            // foot stays on Super+Return. --class gives the window its own
            // app-id so a niri window rule can float it without catching every
            // other kitty.
            command: ["kitty", "--class", "bluetui", "-e", "bluetui"]
        }
    }

    // Display picker: resolution, scale and brightness, per monitor.
    //
    // Wider than the others at 460, because the brightness row is ten chips
    // across and wrapping it would break the one thing that makes a segmented
    // row readable -- that it is a single line you scan left to right.
    PanelWindow {
        visible: root.openPanel === "display"
        // Open on the monitor whose bar was pressed, rather than leaving it to
        // the compositor. The other pickers are screenless and land wherever
        // niri puts them, which is fine when their content is the same
        // everywhere -- one wifi list, one bluetooth list. This one's content is
        // per monitor and ordered by root.activeOutput, so it opening anywhere
        // other than the screen it is describing would be actively misleading.
        //
        // null is the unset value, i.e. back to compositor choice, and is what
        // this falls to before the first press and during a hotplug.
        screen: {
            const want = root.activeOutput;
            if (!want)
                return null;
            const s = Quickshell.screens.find(x => x.name === want);
            return s ? s : null;
        }
        WlrLayershell.layer: WlrLayer.Overlay
        exclusionMode: ExclusionMode.Ignore
        anchors {
            top: true
            right: true
        }
        margins {
            top: 34
            right: 8
        }
        implicitWidth: 460
        implicitHeight: dispCol.implicitHeight + 20
        color: root.bg

        Column {
            id: dispCol
            anchors.fill: parent
            anchors.margins: 10
            spacing: 6

            Repeater {
                model: disp.list

                Column {
                    id: monCol
                    required property var modelData
                    readonly property var o: modelData
                    readonly property bool internal: disp.isInternal(o)
                    readonly property int bright: disp.bright[o.name] !== undefined ? disp.bright[o.name] : -1

                    width: dispCol.width
                    spacing: 4

                    // Make and model, with the connector in brackets. Both
                    // matter: the name is what you recognise the monitor by,
                    // the connector is what tells you which of two identical
                    // ones you are about to change.
                    PickerHeading {
                        width: monCol.width
                        elide: Text.ElideRight
                        color: root.accent
                        text: {
                            const o = monCol.o;
                            const id = [o.make, o.model].filter(s => s && s.length > 0).join(" ");
                            return (id.length > 0 ? id : o.name) + "  (" + o.name + ")";
                        }
                    }

                    PickerHeading {
                        text: "Resolution"
                    }

                    Repeater {
                        model: disp.modeList(monCol.o)

                        PickerRow {
                            id: modeRow
                            required property var modelData
                            readonly property string str: disp.modeStr(modelData)
                            readonly property bool isCurrent: str === disp.curMode(monCol.o)
                            width: monCol.width
                            onActivated: {
                                disp.niri(monCol.o.name, "mode", modeRow.str);
                                disp.remember(monCol.o, "mode", modeRow.str);
                            }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.left: parent.left
                                anchors.leftMargin: root.inset
                                width: parent.width - 12
                                elide: Text.ElideRight
                                color: modeRow.isCurrent ? root.accent : root.fg
                                font.family: root.mono
                                font.pixelSize: 12
                                // Refresh rounded to whole Hz. The fractional
                                // part is never the thing being chosen here --
                                // modeList already kept only the fastest timing
                                // per resolution -- and "59.997 Hz" next to
                                // "30.000 Hz" reads as precision that is not
                                // being offered.
                                text: {
                                    const m = modeRow.modelData;
                                    return m.width + "x" + m.height + "   " + Math.round(m.refresh_rate / 1000) + " Hz" + (m.is_preferred ? "   (EDID preferred)" : "");
                                }
                            }
                        }
                    }

                    // The disclosure row for everything at or below 1080p.
                    // Shown only when there is something to disclose, so a
                    // monitor offering nothing but its native mode gets no
                    // dangling control.
                    PickerRow {
                        readonly property int hidden: disp.hiddenCount(monCol.o)
                        readonly property bool open: disp.expanded[monCol.o.name] === true

                        width: monCol.width
                        visible: hidden > 0 || open
                        height: visible ? 26 : 0
                        onActivated: disp.toggleExpanded(monCol.o.name)

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.left: parent.left
                            anchors.leftMargin: root.inset
                            color: root.dim
                            font.family: root.mono
                            font.pixelSize: 12
                            // nf-md-chevron_up / _down: the chevron points the
                            // way the list is about to move, which is the
                            // convention every disclosure widget uses.
                            text: parent.open ? root.icon(0xF0143) + "  Show fewer" : root.icon(0xF0140) + "  Show " + parent.hidden + " more (1080p and below)"
                        }
                    }

                    // Scale. Integers are exact for every client; the
                    // fractional steps are there because 2 on a 4K panel this
                    // size is often too big, and are the ones wayland only
                    // approximates -- a client without fractional-scale-v1
                    // renders at 2x and gets scaled down, so text is softer
                    // than at either 1 or 2.
                    PickerHeading {
                        text: "Scale"
                    }

                    Row {
                        leftPadding: root.inset
                        spacing: 4

                        Repeater {
                            model: [1, 1.25, 1.5, 1.75, 2, 2.5, 3]

                            SegCell {
                                required property var modelData
                                label: String(modelData)
                                active: Math.abs(modelData - monCol.o.logical.scale) < 0.001
                                onActivated: {
                                    disp.niri(monCol.o.name, "scale", modelData);
                                    disp.remember(monCol.o, "scale", modelData);
                                }
                            }
                        }
                    }

                    PickerHeading {
                        text: {
                            if (monCol.internal)
                                return "Brightness";
                            if (disp.ddc[monCol.o.name] === undefined)
                                return "Brightness   (no DDC/CI -- use the monitor's own buttons)";
                            return "Brightness   (DDC/CI)";
                        }
                    }

                    Row {
                        leftPadding: root.inset
                        spacing: 4
                        // Steps of 10 rather than a finer grid: on the internal
                        // panel the backlight has 90 hardware levels, so a
                        // finer UI step would not always move it, and on DDC
                        // every step costs a round trip to the monitor.
                        //
                        // Starts at 10, not 0. Zero on an external monitor over
                        // DDC is a black screen you then have to find the
                        // monitor's physical buttons to undo -- and on the
                        // internal panel it is a black screen with no buttons
                        // at all.
                        Repeater {
                            model: [10, 20, 30, 40, 50, 60, 70, 80, 90, 100]

                            SegCell {
                                required property var modelData
                                label: String(modelData)
                                available: disp.hasBrightness(monCol.o)
                                // The nearest step below the real value, so a
                                // panel sitting at 87 lights the 80 chip rather
                                // than nothing at all.
                                active: monCol.bright >= 0 && Math.floor(Math.max(10, monCol.bright) / 10) * 10 === modelData
                                onActivated: disp.setBrightness(monCol.o, modelData)
                            }
                        }
                    }
                }
            }

            // Footer. Says what the panel is doing behind the user's back,
            // because "it remembered" is invisible when it works and
            // inexplicable when it does not.
            PickerHeading {
                width: dispCol.width
                wrapMode: Text.WordWrap
                text: {
                    const n = Object.keys(disp.saved).length;
                    if (n === 0)
                        return "Nothing saved yet -- pick a resolution, scale or brightness and it will be reapplied when this monitor is next plugged in.";
                    return "Saved for " + n + " monitor" + (n === 1 ? "" : "s") + "; reapplied on plug-in.";
                }
            }
        }
    }

    // System page: what this machine is, in hardware and in software.
    //
    // Screenless, unlike the display picker. Nothing on it is per monitor, so
    // there is no monitor it would be wrong to open on.
    PanelWindow {
        visible: root.openPanel === "system"
        WlrLayershell.layer: WlrLayer.Overlay
        exclusionMode: ExclusionMode.Ignore
        anchors {
            top: true
            right: true
        }
        margins {
            top: 34
            right: 8
        }
        implicitWidth: 530
        implicitHeight: sysCol.implicitHeight + 20
        color: root.bg

        Column {
            id: sysCol
            anchors.fill: parent
            anchors.margins: 10
            // Between the two sections. The rows inside each are tighter --
            // they are one table, not a list of separate facts.
            spacing: 10

            Column {
                id: hwCol
                width: sysCol.width
                spacing: 2

                PickerHeading {
                    color: root.accent
                    text: "Hardware"
                }

                Repeater {
                    model: info.hardware

                    InfoRow {
                        required property var modelData
                        width: hwCol.width
                        label: modelData.k
                        value: modelData.v
                    }
                }
            }

            Column {
                id: swCol
                width: sysCol.width
                spacing: 2

                PickerHeading {
                    color: root.accent
                    text: "Software"
                }

                Repeater {
                    model: info.software

                    InfoRow {
                        required property var modelData
                        width: swCol.width
                        label: modelData.k
                        value: modelData.v
                    }
                }
            }
        }
    }

    // Battery page: one switch and the one number that is not already on the
    // bar or the system page.
    //
    // Percentage, health and cycle count are deliberately not repeated here --
    // they are on the system page, and the standing rule in this file is that
    // two places showing the same number must not be able to disagree. Narrower
    // than the 530 the system page uses, because two rows of content in 530px
    // is mostly empty panel.
    PanelWindow {
        visible: root.openPanel === "battery"
        WlrLayershell.layer: WlrLayer.Overlay
        exclusionMode: ExclusionMode.Ignore
        anchors {
            top: true
            right: true
        }
        margins {
            top: 34
            right: 8
        }
        implicitWidth: 360
        implicitHeight: batCol.implicitHeight + 20
        color: root.bg

        Column {
            id: batCol
            anchors.fill: parent
            anchors.margins: 10
            spacing: 6

            // Segmented chips rather than an On/Off row, matching the DNS
            // picker. Two named modes both spelled out and one of them lit is
            // easier to read at a glance than a single label whose state lives
            // in one word at the far end of the panel -- and it makes the
            // default visible, which On/Off does not: "Auto" says there is a
            // normal behaviour to go back to.
            //
            // Auto is first for the same reason DHCP is first in that row: it
            // is the unmodified state, and the overrides follow it.
            PickerHeading { text: "Sleep" }

            Row {
                leftPadding: root.inset
                spacing: 4

                // `awake.running` is both the state and the control -- there is
                // no separate bool that could disagree with whether the lock is
                // actually held, so these chips cannot show a mode the machine
                // is not in.
                SegCell {
                    label: "Auto"
                    active: !awake.running
                    onActivated: awake.running = false
                }

                SegCell {
                    label: "Stay awake"
                    active: awake.running
                    // Same caution yellow the bar cell turns, so the chip you
                    // selected and the colour you then see on the bar are
                    // visibly the same fact.
                    activeColor: root.caution
                    onActivated: awake.running = true
                }
            }

            // Says what the selected mode actually does, because "stay awake"
            // alone does not distinguish it from "keep the screen on" -- which
            // is the opposite of the intent here.
            Text {
                width: batCol.width
                leftPadding: root.inset
                rightPadding: root.inset
                wrapMode: Text.WordWrap
                color: root.dim
                font.family: root.mono
                font.pixelSize: 10
                text: awake.running
                    ? "Idle and lid close will not suspend. The screen still blanks and locks. Stays on across shell restarts, but not across a reboot until you log in."
                    : "Suspends after 15m idle, or on lid close."
            }

            // Time remaining. UPower reports 0 for "no estimate" rather than a
            // null, and it does that whenever the battery is neither charging
            // nor discharging -- on AC at full charge it is 0 in both
            // directions. Printing that verbatim gives "0m", which reads as an
            // imminent shutdown. So the state drives the label and the seconds
            // only ever appear when they mean something.
            InfoRow {
                width: batCol.width
                labelWidth: 78
                label: "Remaining"
                value: {
                    if (!info.batPresent)
                        return "No battery";
                    const b = info.bat;
                    const fmt = s => {
                        const h = Math.floor(s / 3600);
                        const m = Math.round((s % 3600) / 60);
                        return h > 0 ? h + "h " + m + "m" : m + "m";
                    };
                    if (b.state === UPowerDeviceState.Discharging)
                        return b.timeToEmpty > 0 ? fmt(b.timeToEmpty) + " left" : "Estimating";
                    if (b.state === UPowerDeviceState.Charging)
                        return b.timeToFull > 0 ? fmt(b.timeToFull) + " to full" : "Charging";
                    if (b.state === UPowerDeviceState.FullyCharged)
                        return "Full, on AC";
                    return "On AC";
                }
            }
        }
    }

    // World clock.
    PanelWindow {
        visible: root.openPanel === "clock"
        WlrLayershell.layer: WlrLayer.Overlay
        exclusionMode: ExclusionMode.Ignore
        anchors.top: true
        margins.top: 34
        implicitWidth: 240
        implicitHeight: clockCol.implicitHeight + 20
        color: root.bg

        Column {
            id: clockCol
            anchors.fill: parent
            anchors.margins: 10
            spacing: 6

            Repeater {
                model: root.zones

                Row {
                    required property var modelData
                    width: clockCol.width

                    Text {
                        width: 130
                        text: parent.modelData.label
                        color: root.dim
                        font.family: root.mono
                        font.pixelSize: 12
                    }

                    Text {
                        text: world.times[parent.modelData.label] ?? "--:--"
                        color: root.fg
                        font.family: root.mono
                        font.pixelSize: 12
                    }
                }
            }
        }
    }
}
