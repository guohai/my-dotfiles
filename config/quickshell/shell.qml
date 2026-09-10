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
    readonly property color hover: "#313244"
    readonly property string mono: "JetBrainsMono Nerd Font"

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

        // Connected, then paired, then whatever the scan turned up.
        readonly property var list: Bluetooth.devices.values.slice().sort((a, b) => (b.connected - a.connected) || (b.paired - a.paired) || a.name.localeCompare(b.name))

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
                    onClicked: root.openPanel = root.openPanel === "clock" ? "" : "clock"
                }
            }

            // ---- right: status ----
            Row {
                anchors.right: parent.right
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                spacing: 14

                Cell {
                    text: "CPU " + sys.cpuPct.toFixed(0) + "%"
                }
                Cell {
                    text: "RAM " + sys.memPct.toFixed(0) + "%"
                }
                Cell {
                    text: "DISK " + sys.diskPct
                }

                // Volume. Scroll to adjust, click to mute, right-click to pick
                // an output device -- roughly the macOS menu-bar behaviour.
                Cell {
                    id: volCell
                    color: root.openPanel === "audio" ? root.accent : root.fg
                    text: {
                        const a = audio.sink?.audio;
                        if (!a)
                            return "VOL --";
                        return a.muted ? "VOL Muted" : "VOL " + Math.round(a.volume * 100) + "%";
                    }

                    MouseArea {
                        anchors.fill: parent
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        onClicked: mouse => {
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
                Cell {
                    color: root.openPanel === "wifi" ? root.accent : root.fg
                    text: !Networking.wifiEnabled ? "WIFI off" : net.active ? "WIFI " + net.active.name : "WIFI --"

                    MouseArea {
                        anchors.fill: parent
                        onClicked: root.openPanel = root.openPanel === "wifi" ? "" : "wifi"
                    }
                }

                // Bluetooth: bluez via Quickshell.Bluetooth. Click for the
                // device picker.
                Cell {
                    color: root.openPanel === "bt" ? root.accent : root.fg
                    text: {
                        const ad = bt.adapter;
                        if (!ad)
                            return "BT --";
                        if (!ad.enabled)
                            return "BT off";
                        return "BT " + bt.connectedDevices.length;
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: root.openPanel = root.openPanel === "bt" ? "" : "bt"
                    }
                }

                // Battery: upower. displayDevice is the aggregate the daemon
                // designates for display; on a laptop that is BAT0.
                Cell {
                    readonly property var bat: UPower.displayDevice
                    color: bat && bat.percentage <= 0.15 && bat.state === UPowerDeviceState.Discharging ? root.bad : root.fg
                    text: {
                        if (!bat || !bat.isLaptopBattery)
                            return "";
                        const pct = Math.round(bat.percentage * 100) + "%";
                        const charging = bat.state === UPowerDeviceState.Charging || bat.state === UPowerDeviceState.FullyCharged;
                        return (charging ? "CHG " : "BAT ") + pct;
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
