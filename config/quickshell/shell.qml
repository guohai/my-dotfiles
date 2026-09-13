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
    readonly property color hover: "#313244"
    readonly property string mono: "JetBrainsMono Nerd Font"

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

    // Which popup is open, or "" for none. One string rather than a bool per
    // popup so opening one always closes the others.
    property string openPanel: ""

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

    // ---- system stats ---------------------------------------------------
    // Quickshell has no cpu/mem/disk module; these come from /proc via
    // FileView. procfs does not emit inotify events, so watchChanges would
    // never fire -- poll with a Timer and reload() instead.
    Scope {
        id: sys

        property real cpuPct: 0
        property real memPct: 0
        property string diskPct: "--"

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
                onStreamFinished: sys.diskPct = text.split("\n")[1].trim()
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

    // ---- audio ----------------------------------------------------------
    // PwObjectTracker is mandatory, not decorative: Quickshell only binds a
    // node's properties while something tracks it. Without this the volume
    // reads zero and never updates.
    PwObjectTracker {
        objects: [Pipewire.defaultAudioSink]
    }

    Scope {
        id: audio
        readonly property var sink: Pipewire.defaultAudioSink
        // Real output devices only: isStream filters out per-application
        // playback nodes, which are also sinks in pipewire's model. A
        // bluetooth headset appears here once wireplumber has routed it.
        readonly property var sinks: Pipewire.nodes.values.filter(n => n.isSink && !n.isStream)

        function bump(delta) {
            if (!sink?.audio)
                return;
            sink.audio.muted = false;
            sink.audio.volume = Math.max(0, Math.min(1, sink.audio.volume + delta));
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

        // Connected first, then strongest. Copy before sorting: .values hands
        // back the live model array and sort() would reorder it in place.
        readonly property var list: dev ? dev.networks.values.slice().sort((a, b) => (b.connected - a.connected) || (b.signalStrength - a.signalStrength)) : []

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

    // ---- the bar --------------------------------------------------------
    Variants {
        model: Quickshell.screens

        PanelWindow {
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
                IconCell {
                    glyph: root.icon(0xF4BC)
                    value: sys.cpuPct.toFixed(0) + "%"
                }
                IconCell {
                    // nf-md-expansion_card_variant -- reads as a RAM stick.
                    glyph: root.icon(0xF0FB2)
                    value: sys.memPct.toFixed(0) + "%"
                }
                IconCell {
                    // nf-md-harddisk
                    glyph: root.icon(0xF02CA)
                    value: sys.diskPct
                }

                // Volume. Scroll to adjust, click to mute, right-click to pick
                // an output device -- roughly the macOS menu-bar behaviour.
                //
                // The speaker fills up with the level the way macOS's does, so
                // the glyph carries the volume too and the number is
                // confirmation rather than the only signal. Muted is its own
                // glyph (the crossed-out speaker) rather than the word, which
                // is the one state worth recognising without reading.
                IconCell {
                    id: volCell
                    readonly property var a: audio.sink?.audio
                    readonly property int vol: a ? Math.round(a.volume * 100) : 0

                    tint: root.openPanel === "audio" ? root.accent : root.fg
                    glyph: {
                        // nf-md-volume_off, then _low / _medium / _high.
                        if (!a || a.muted || vol === 0)
                            return root.icon(0xF0581);
                        return root.icon(vol < 34 ? 0xF057F : vol < 67 ? 0xF0580 : 0xF057E);
                    }
                    value: !a ? "--" : a.muted ? "" : vol + "%"

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
                // Text survives only for the state the glyph cannot express:
                // "--" for radio-on-but-associated-with-nothing. Radio off is
                // the struck-through glyph with no text, since "off" next to a
                // crossed-out wifi icon says the same thing twice.
                IconCell {
                    // accent means connected, not merely panel-open. The picker
                    // is a large popup on screen when open, so it does not need
                    // the tint to announce itself as well.
                    tint: net.active || root.openPanel === "wifi" ? root.accent : root.fg
                    // nf-md-wifi / nf-md-wifi_off
                    glyph: root.icon(Networking.wifiEnabled ? 0xF05A9 : 0xF05AA)
                    value: !Networking.wifiEnabled || net.active ? "" : "--"

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

                // Battery: upower. displayDevice is the aggregate the daemon
                // designates for display; on a laptop that is BAT0.
                //
                // Glyph and wording are deliberately identical to the lock
                // screen's --batstr, which draws the same Material Design cells
                // straight from /sys/class/power_supply -- see the battext()
                // and battery_status() hunks in
                // nixos/pkgs/swaylock-effects-weekday.patch. The two are read
                // within seconds of each other every time the machine locks, so
                // any disagreement between them reads as a bug in one of them.
                // Change one, change the other.
                //
                // The numbers agree because both divide by what the cell holds
                // *today* rather than by its design capacity: upower does that
                // in the daemon, the patch computes charge_now/charge_full by
                // hand for the same reason. On this machine -- 68% health after
                // 518 cycles -- trusting the kernel's own `capacity` attribute
                // instead would have put the lock screen 26 points under the
                // bar.
                IconCell {
                    readonly property var bat: UPower.displayDevice
                    readonly property bool present: bat && bat.isLaptopBattery
                    // "Full" counts as charging, matching the patch, which
                    // treats a status of Charging or Full the same way. On the
                    // bolt there is no level to draw anyway.
                    readonly property bool charging: present
                        && (bat.state === UPowerDeviceState.Charging
                            || bat.state === UPowerDeviceState.FullyCharged)
                    readonly property int pct: present
                        ? Math.max(0, Math.min(100, Math.round(bat.percentage * 100)))
                        : 0

                    // nf-md-battery is U+F0079 (full) and nf-md-battery_10
                    // ..._90 run F007A..F0082, which is why the tenths bucket
                    // maps to F0079+n for everything in between.
                    // nf-md-battery_charging is F0084 and
                    // nf-md-battery_outline F008E.
                    //
                    // The empty outline for the last 10% is the one place this
                    // and the lock screen were allowed to drift from the
                    // original table, and the patch was changed to match rather
                    // than left alone.
                    glyph: {
                        if (!present)
                            return "";
                        if (charging)
                            return root.icon(0xF0084);
                        const tenths = Math.floor(pct / 10);
                        if (tenths === 0)
                            return root.icon(0xF008E);
                        if (tenths >= 10)
                            return root.icon(0xF0079);
                        return root.icon(0xF0079 + tenths);
                    }

                    // Colour is bar-only: swaylock draws the whole battery line
                    // in --text-color and has no per-line colour option, so the
                    // lock screen shows the same glyph in the same grey. The
                    // thresholds still line up with the icon, so an empty cell
                    // is always red and a one-bar cell is always peach.
                    tint: {
                        if (!present || charging)
                            return root.fg;
                        if (pct < 10)
                            return root.bad;
                        if (pct < 20)
                            return root.warn;
                        return root.fg;
                    }

                    // "󰂁 63%" -- the lock screen's format string is
                    // "{icon} {p}%", which expands to exactly this.
                    value: present ? pct + "%" : ""
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

    // Audio output picker.
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
                        anchors.leftMargin: 6
                        width: parent.width - 12
                        elide: Text.ElideRight
                        color: sinkRow.isCurrent ? root.accent : root.fg
                        font.family: root.mono
                        font.pixelSize: 12
                        text: (sinkRow.isCurrent ? "* " : "  ") + (sinkRow.modelData.description || sinkRow.modelData.nickname || sinkRow.modelData.name)
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
                    anchors.leftMargin: 6
                    color: root.dim
                    font.family: root.mono
                    font.pixelSize: 12
                    text: "  Open pavucontrol (per-app mixer)..."
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
                    anchors.leftMargin: 6
                    color: root.dim
                    font.family: root.mono
                    font.pixelSize: 11
                    text: "Wi-Fi"
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.right: parent.right
                    anchors.rightMargin: 6
                    color: !Networking.wifiHardwareEnabled ? root.bad : Networking.wifiEnabled ? root.accent : root.dim
                    font.family: root.mono
                    font.pixelSize: 11
                    text: !Networking.wifiHardwareEnabled ? "blocked by hardware switch" : Networking.wifiEnabled ? "on" : "off"
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
                        anchors.leftMargin: 6
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
                        anchors.rightMargin: 6
                        color: root.dim
                        font.family: root.mono
                        font.pixelSize: 11
                        text: {
                            const n = netRow.modelData;
                            if (n.stateChanging)
                                return ConnectionState.toString(n.state) + "...";
                            if (n.connected)
                                return "connected";
                            if (n.known)
                                return "saved";
                            return n.security === WifiSecurityType.Open ? "open" : "locked";
                        }
                    }
                }
            }

            // Passphrase prompt. Plain TextInput rather than QtQuick.Controls
            // TextField, to avoid pulling the Controls style stack into the
            // shell for one widget.
            Column {
                width: wifiCol.width
                spacing: 4
                visible: net.pskTarget !== null

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
                        echoMode: TextInput.Password
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
                                net.pskTarget = null;
                                text = "";
                            }
                        }
                        Keys.onEscapePressed: {
                            net.pskTarget = null;
                            text = "";
                        }
                    }
                }

                PickerHeading {
                    text: "Enter to connect, Esc to cancel"
                }
            }

            Text {
                width: wifiCol.width
                visible: net.error !== ""
                wrapMode: Text.Wrap
                color: root.bad
                font.family: root.mono
                font.pixelSize: 11
                text: net.error
            }

            PickerHeading {
                width: wifiCol.width
                wrapMode: Text.Wrap
                text: net.dev ? "Scanning on " + net.dev.name + " -- right-click a saved network to forget it" : "Waiting for NetworkManager..."
            }
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
                    anchors.leftMargin: 6
                    color: root.dim
                    font.family: root.mono
                    font.pixelSize: 11
                    text: "Bluetooth"
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.right: parent.right
                    anchors.rightMargin: 6
                    color: !bt.adapter ? root.bad : bt.adapter.enabled ? root.accent : root.dim
                    font.family: root.mono
                    font.pixelSize: 11
                    // No adapter at all means bluez is not on the bus, which is
                    // a different problem from the adapter being powered down.
                    text: !bt.adapter ? "bluez not running" : bt.adapter.enabled ? "on" : "off"
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
                        anchors.leftMargin: 6
                        anchors.right: btState.left
                        anchors.rightMargin: 8
                        elide: Text.ElideRight
                        color: btRow.modelData.connected ? root.accent : root.fg
                        font.family: root.mono
                        font.pixelSize: 12
                        text: (btRow.modelData.connected ? "* " : "  ") + btRow.modelData.name
                    }

                    Text {
                        id: btState
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.right: parent.right
                        anchors.rightMargin: 6
                        color: root.dim
                        font.family: root.mono
                        font.pixelSize: 11
                        text: {
                            const d = btRow.modelData;
                            if (d.pairing)
                                return "pairing...";
                            if (d.state === BluetoothDeviceState.Connecting)
                                return "connecting...";
                            if (d.state === BluetoothDeviceState.Disconnecting)
                                return "disconnecting...";
                            // batteryAvailable needs bluez's experimental
                            // features, which configuration.nix turns on --
                            // most headsets report charge over that interface.
                            if (d.connected && d.batteryAvailable)
                                return "connected  " + Math.round(d.battery * 100) + "%";
                            if (d.connected)
                                return "connected";
                            return d.paired ? "paired" : "new";
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
                    anchors.leftMargin: 6
                    color: bt.scanning ? root.accent : root.dim
                    font.family: root.mono
                    font.pixelSize: 11
                    text: bt.scanning ? "  Scanning for devices... (click to stop)" : "  Scan for new devices"
                }

                // The beacons are hidden, not silently dropped. Without a count
                // here a scan that turns up nothing looks like a dead radio,
                // when in fact it found fifty devices and none of them were
                // willing to say what they were.
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.right: parent.right
                    anchors.rightMargin: 6
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
                    anchors.leftMargin: 6
                    color: root.dim
                    font.family: root.mono
                    font.pixelSize: 12
                    text: "  Open blueman-manager (profiles, codecs)..."
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
            command: ["blueman-manager"]
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
