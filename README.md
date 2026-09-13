# my-dotfiles

A complete NixOS + [niri](https://github.com/YaLTeR/niri) Wayland desktop, with a
Mac-style keyboard layer, a hand-written [Quickshell](https://quickshell.org) bar,
and a blurred-wallpaper lock screen.

Built and running on NixOS **26.05** on a MacBookPro14,1 (13-inch Intel, 2017).
Everything except the camera driver and the bootloader is hardware-agnostic.

---

## What's installed

Everything below is declared in `nixos/configuration.nix` — there is nothing to
`nix-env -i` afterwards. Delete what you don't want before rebuilding.

### Desktop

| | |
| --- | --- |
| **niri** | Scrolling-tiling Wayland compositor. The window manager. |
| **Quickshell** | The top bar — clock, battery, CPU/mem/disk, wifi, bluetooth, audio, clipboard history. Status cells are Nerd Font icons rather than `CPU`/`RAM`/`BAT` labels, and several of them carry state in the glyph itself (battery fill level, volume level, muted, radio off). Written from scratch in `config/quickshell/shell.qml`. |
| **fuzzel** | Application launcher (`Super+Space`). |
| **mako** | Notification daemon. |
| **wpaperd** | Wallpaper daemon (a 4K mountain landscape). |
| **greetd + tuigreet** | Login screen on the TTY, launches `niri-session`. |
| **swaylock-effects + swayidle** | Lock screen with blurred wallpaper + idle/sleep handling. |
| **xremap** | The Mac-style ⌘ key layer. Runs as a user service. |
| **JetBrains Mono Nerd Font**, **Noto Color Emoji** | System fonts. |

### Terminal and shell

| | |
| --- | --- |
| **kitty** | Primary terminal. Mac keybinds, vertical tab bar, `Cmd+T`/`Cmd+W`/`Cmd+1..9`. |
| **foot** | Second, lighter Wayland terminal. |
| **fish** | Default login shell, with autosuggestions and history search. Bash history was imported. |

### Applications

| | |
| --- | --- |
| **Google Chrome** | Browser (Wayland/Ozone). |
| **Zed** | Editor — fast, GPU-rendered, tree-sitter syntax highlighting, Mac keymap. |
| **mpv** | Video player, with a hardware-decode + high-quality-scaling config. |
| **Nautilus** | GNOME file manager, plus `nautilus-open-any-terminal` wired to kitty. |
| **pavucontrol** | Full audio mixer, for when the bar's picker isn't enough. |
| **luvus** | Vendored from `nixos/pkgs/luvus.nix` — not in nixpkgs. |
| **Claude Code** | Anthropic's CLI. |

### Screenshots, recording, media

| | |
| --- | --- |
| **grim + slurp + satty** | Screenshots. `⌘+Shift+3` whole screen, `⌘+Shift+4` drag a region — both open satty to annotate, then copy to the clipboard and save to `~/Pictures/Screenshots/`. niri's own `Print` / `Ctrl+Print` / `Alt+Print` are also bound — picker / whole screen / focused window, saved straight to disk with no annotation step — but an Apple keyboard has no Print key. |
| **wf-recorder** | Screen recording, driven by the `screen-record` toggle (defined in `configuration.nix`). `⌘+Shift+5` records the focused screen, `⌘+Ctrl+Shift+5` drags a region. Press the same chord again to stop — either one stops a recording, whichever started it. Video goes to `~/Videos/Screen Recording <date>.mp4` and its path lands on the clipboard when you stop. Records system audio by default (`screen-record full mute` from a shell for silent). H.264 on the GPU via VA-API, falling back to x264 on the CPU. |
| **ffmpeg-full** | Full ffmpeg with every codec and filter enabled. |
| **playerctl** | Media keys (play/pause/next) against MPRIS. |
| **wl-clipboard + cliphist + wl-clip-persist** | Clipboard, searchable clipboard history, and clipboard survival after the source app closes. |

### System services

| | |
| --- | --- |
| **PipeWire** (+ ALSA, PulseAudio, rtkit) | Audio stack. |
| **BlueZ + blueman** | Bluetooth, with the applet autostarted. A `bluetooth-uart-recover` unit re-probes the controller at boot when it fails to come up — see below. |
| **upower**, **power-profiles-daemon** | Battery reporting and power profile switching. |
| **brightnessctl** | Backlight keys. |
| **gvfs** | Trash, MTP, and network mounts for Nautilus. |
| **polkit** | Privilege prompts for GUI apps. |
| **facetimehd** | Apple Intel Mac internal camera. *Delete this on any other machine.* |

### Networking

| | |
| --- | --- |
| **NetworkManager** | Wifi and wired, driven from the bar. |
| **NetBird** | Overlay VPN / mesh network. Starts at boot; log in with `netbird up`. |
| **OpenSSH** | sshd with password auth on, `PermitRootLogin = "prohibit-password"`, firewall port opened. |

### Development

| | |
| --- | --- |
| **git**, **Node.js** | |
| **tig** | ncurses browser for git history. `tig` in any working tree. |
| **gh** | GitHub CLI — PRs, issues, releases. `gh auth login` also sets it up as a git credential helper over HTTPS. Note it writes an OAuth token in plaintext to `~/.config/gh/hosts.yml`. |
| **Docker** | With weekly `autoPrune`. Your user is in the `docker` group. |
| **nix-ld** | Lets unpatched dynamically-linked binaries (downloaded toolchains, language servers) run on NixOS. |

---

## What's in here

| Path | What it is |
| --- | --- |
| `nixos/configuration.nix` | The whole system. Also contains the entire home-manager config inline. |
| `nixos/pkgs/luvus.nix` | Vendored package for [luvus](https://luvus.dev), not yet in nixpkgs. |
| `nixos/pkgs/swaylock-effects-weekday.patch` | Adds `--weekstr` and `--batstr` to swaylock-effects, for a four-line lock clock with a live battery readout. |
| `config/niri/config.kdl` | niri compositor: keybinds, layout, window rules. Hand-managed. |
| `config/quickshell/shell.qml` | The status bar: clock, battery, CPU/mem/disk, wifi + bluetooth + audio pickers, clipboard history. Hand-managed. |
| `config/xremap/config.yml` | Mac-style Cmd (⌘) key remapping for GUI apps. Hand-managed. |

### Files that are deliberately NOT here

**These are generated — do not copy them from another machine.**

`kitty.conf`, `foot.ini`, `fish/config.fish`, `mpv.conf`, `zed/settings.json`,
`zed/keymap.json` and `wpaperd/wallpaper.toml` are all produced by home-manager
*from* `configuration.nix`. Restoring `configuration.nix` recreates them. Copying
them by hand just creates two sources of truth that drift apart.

`hardware-configuration.nix` is **excluded on purpose**: it contains this
laptop's filesystem UUIDs. Generate your own with `nixos-generate-config`.
Never copy someone else's.

---

## Restoring on a new machine

### 0. Install NixOS itself — from the **minimal** ISO, with no desktop

Download the **Minimal ISO image** from [nixos.org/download](https://nixos.org/download/),
not the GNOME or Plasma graphical one. Match the release to this config:
`system.stateVersion` here is **26.05**, and home-manager is pinned to
`release-26.05`, so nixpkgs has to be the 26.05 channel or the two will not agree.

Three reasons the graphical installer is the wrong starting point:

- **Its work gets thrown away.** Calamares writes its own
  `/etc/nixos/configuration.nix` with `services.desktopManager.gnome` and GDM in
  it. Step 3 below overwrites that file wholesale. You will have downloaded and
  built an entire GNOME desktop that never runs again, and it sits in the Nix
  store until you `nix-collect-garbage -d`.
- **This config brings its own login screen.** `services.greetd` + tuigreet
  launches `niri-session` from a TTY. A second display manager is not a conflict
  you have to resolve — it just should never have been installed.
- **The minimal ISO drops you exactly where the rest of this README expects
  you.** Steps 1–5 are all TTY work, and greetd is a TTY login. There is no
  point in the install being graphical when the finished system's first screen
  is text.

The short version of a minimal install (read the
[NixOS manual](https://nixos.org/manual/nixos/stable/#sec-installation) for
partitioning — it is machine-specific and easy to get wrong):

```bash
# ...partition and format, then mount the root at /mnt...
sudo nixos-generate-config --root /mnt
sudo nixos-install                 # prompts for a root password
reboot
```

Log in as **root** on the TTY after the reboot. Your own account does not exist
yet — it gets created by step 3, and even then without a password (see the note
there). Wifi on a minimal system is `nmtui` or `nmcli`. `git` is on the installer
image but *not* on the system you just installed, so the clone below borrows it
from a temporary shell.

### 1. Clone this repo and generate your hardware config

```bash
nix-shell -p git --run 'git clone https://github.com/guohai/my-dotfiles ~/my-dotfiles'
cd ~/my-dotfiles
```

`--run` matters: a bare `nix-shell -p git` opens an interactive subshell, so the
lines pasted after it would not execute until you exit it.

**Generate your own hardware config** (do not skip this):

```bash
sudo nixos-generate-config
```

If you came from step 0, `nixos-install` already wrote this file and you can skip
the command — it is here for the other path, applying this repo to a NixOS
machine you already have.

`configuration.nix` imports `./hardware-configuration.nix`, which is not in this
repo on purpose. If it is missing, the very first build fails with:

```
error: path '.../hardware-configuration.nix' does not exist
```

That is expected, not a broken repo. `nixos-generate-config` writes the file to
`/etc/nixos/`, which is where step 3 puts everything else.

### 2. Read the portability header

At the top of `nixos/configuration.nix` — edit what applies to you. Every
machine-specific line is also marked inline:

```bash
grep -n 'PORTABILITY:' nixos/configuration.nix
```

At minimum you will want to change the **username** (it is `brent` in this repo),
the **timezone**, and delete the **FaceTime HD camera** block unless you are also
on an Intel Mac.

### 3. Install the system — as root

```bash
# Everything under nixos/pkgs/ is referenced by configuration.nix as a
# relative path. Copy the whole directory -- missing any one file is an
# eval error before the build even starts, e.g.
#   error: path '/etc/nixos/pkgs/swaylock-effects-weekday.patch' does not exist
sudo mkdir -p /etc/nixos/pkgs
sudo cp nixos/configuration.nix /etc/nixos/configuration.nix
sudo cp nixos/pkgs/*            /etc/nixos/pkgs/

sudo nixos-rebuild switch

# The account is created without a password. Set one before logging out, or
# greetd will not let you in.
sudo passwd YOURNAME
```

This is the step that creates your user account, so nothing before it can be
done *as* that user.

### 4. Deploy the three hand-managed configs — as your own user

Log out of root and log in as `YOURNAME` on the TTY. **Do not run these as
root**: `~` is `/root` there, and the files would land in root's home where
niri, Quickshell and xremap will never look for them. The symptom is a system
that boots to a working desktop with no bar, no keybinds and no Mac key layer,
with nothing in any log to explain it.

```bash
# If you cloned into /root in step 1, you cannot reach it from here -- /root is
# mode 0700. Either hand it over while still root:
#     mv /root/my-dotfiles /home/YOURNAME/ && chown -R YOURNAME: /home/YOURNAME/my-dotfiles
# or just clone it again now, as yourself. git is on the system after step 3.
cd ~/my-dotfiles

# These three are NOT deployed by configuration.nix -- it does not manage
# them, by design (see "Quickshell's shell.qml lives outside the Nix store"
# below).
mkdir -p ~/.config/niri ~/.config/quickshell ~/.config/xremap
cp config/niri/config.kdl      ~/.config/niri/
cp config/quickshell/shell.qml ~/.config/quickshell/
cp config/xremap/config.yml    ~/.config/xremap/
```

### 5. Reboot

The `input` and `uinput` group memberships, the new user services, and the
session environment variables all need a fresh session; the camera block, if you
kept it, needs a new kernel module. Logging out and back in covers the first
group, but on a first install from step 0 you may as well reboot and let greetd
give you the real login screen.

Any pre-existing `kitty.conf` / `foot.ini` / `config.fish` will be renamed to
`.hm-bak` by home-manager on first activation rather than overwritten.

---

## Hardware-specific things, and what to do about them

### Won't work anywhere else — remove it

**FaceTime HD camera** (`hardware.facetimehd.*`)

Apple Intel Macs only. The built-in camera on these machines is not a USB
webcam — it is a Broadcom 1570 sensor on the PCIe bus (`14e4:1570`), which needs
an out-of-tree kernel module plus a firmware blob extracted from a macOS driver
package. The NixOS module also unloads and reloads the driver across
suspend/resume, without which the machine hard-hangs on sleep.

On anything else: **delete both lines.** A normal USB webcam needs no
configuration at all.

**Bootloader** (`boot.loader.systemd-boot`)

Assumes UEFI. A BIOS/legacy machine needs `boot.loader.grub` instead — otherwise
the system builds fine and then refuses to boot.

### Review these

- **`boot.kernelParams = [ "mem_sleep_default=s2idle" ]`** — works on any
  machine, but it is here for an Apple firmware bug and it costs battery. On
  hardware that resumes fine from `deep`, delete it.
- **`time.timeZone`** — set to `America/Los_Angeles`.
- **`console.font = "ter-v32n"`** — a 32px console font, chosen for a HiDPI
  retina panel. On a 1080p screen it is comically large; try `ter-v16n`.
- **Username `brent`** — hardcoded in `users.users.brent`,
  `home-manager.users.brent`, and the `--user brent` flag on tuigreet. Rename
  **all** of them (`sed -i 's/\bbrent\b/YOURNAME/g' nixos/configuration.nix`).
  If you rename only the system account, the build still succeeds and
  home-manager silently configures a user that does not exist.
- **Monitor layout** — the `output "eDP-1"` block in `config/niri/config.kdl` is
  KDL-commented (`/-`) and therefore inactive, so niri auto-detects. Uncomment
  and edit it if you want a fixed resolution/scale. Find your output names with
  `niri msg outputs`.

### Works everywhere

The niri/Quickshell desktop, terminals (kitty + foot), fish, Zed, mpv, the lock
screen, the audio/bluetooth/wifi pickers, clipboard history, screenshots and
screen recording, NetBird, and sshd.

---

## Notable design decisions

These are the ones that are non-obvious enough to be worth knowing before you
change something and wonder why it broke. All of them are explained at length
in comments at the relevant site.

**xremap matches modifiers inexactly.** `exact_match` defaults to `false`, so a
rule bound to `Super-f` *also* fires on `Super+Shift+F` and passes the extra
modifier through. This silently eats keybindings. It is why the lock screen is
on `Super+Ctrl+Q` and not `Super+Alt+L`, and why Zed has no `super-shift-f` bind.

**Terminals are excluded from the Mac key layer.** In kitty/foot the Mac
equivalents of copy/paste are `Ctrl+Shift+C`/`Ctrl+Shift+V`, not `Ctrl+C`/`Ctrl+V`.
A blind `Super+C → Ctrl+C` would send SIGINT and kill the foreground job. So
kitty and foot handle `cmd+c`/`cmd+v` natively and plain `Ctrl+C` is never
rewritten — it keeps working as interrupt.

**The lock screen uses `swaylock-effects`,** a fork whose binary is still named
`swaylock`. Plain swaylock has no `--effect-blur`, `--clock` or `--fade-in`.
A wrapper script picks one of three wallpapers at random per invocation, because
swaylock's config file is read once and cannot express that. All three lock
triggers (keybind, idle timeout, before-sleep) route through the same wrapper so
they look identical.

**The wallpapers are blurred at build time, not at lock time.** swaylock-effects
applies effects to every image *before* it requests `ext_session_lock_v1` — the
ordering is deliberate and commented as such in its `main.c`, since the
alternative is a blank screen while the blur runs. But the wallpapers here are
26–29 megapixel originals, and measured on this machine that was **~270 ms to
decode plus ~1.2 s to blur** on four idle cores. Every lock had a dead second
and a half in front of it, spent with the desktop still on screen and still
accepting input — the session was not actually locked until the blur finished.

So `preblur` scales each wallpaper to the panel and blurs it once, into the Nix
store (ImageMagick is a build input only — it is not installed on the system),
and `--effect-blur` is gone from the lock command. Decode is now **35 ms**.
`--effect-vignette` stays at runtime because it measures 12 ms at panel size.

The radius was carried over rather than guessed: swaylock calls `apply_effects`
with scale hardcoded to `1`, so `--effect-blur 6x3` was three box passes of
radius 6 on the *original*, which cairo then scaled down to the panel — an
effective on-screen radius of `6 × 2560/6264 = 2.45`. Three box passes of radius
`r` approximate a Gaussian of variance `3((2r+1)²−1)/12`, giving `sigma = 2.9`.
Hence `-blur 0x2.9` at panel size. It is now a plain Gaussian sigma in pixels,
which is easier to reason about than radius-times-passes.

`lockWallpaperGeometry` is therefore panel-specific — set it to your own
resolution from `niri msg outputs`.

**Do not put comments between the flags in the lock command.** Every line there
ends in a backslash, so a `#` on its own line does not start a comment — it eats
the rest of the joined line and terminates the command early, silently dropping
every flag after it. Because the wrapper uses `exec`, nothing reports an error;
you just get a lock screen with the wrong colours.

**swaylock-effects is patched for a four-line clock.** Stock swaylock-effects
has exactly two text slots — `--timestr` (large) and `--datestr` (small, under
it) — and both go through `cairo_show_text()`, which ignores `\n`. So

```
󰁿 63%
 Wed
16:24
9 Sep
```

is not reachable from flags alone. `nixos/pkgs/swaylock-effects-weekday.patch`
adds two more slots — `--weekstr` above the time and `--batstr` on top of the
stack — plus a render branch positioned from **font metrics** rather than fixed
fractions of the indicator radius, so the spacing holds up if you change
`--indicator-radius`, `--font-size` or the font. `--batstr` expands `{p}` to the
percentage and `{icon}` to a Nerd Font cell that fills with the charge level (a
bolt while charging), read from `/sys/class/power_supply` **on every frame** —
swaylock re-renders once a second, so the reading tracks while the screen is
locked instead of freezing at lock time. A machine with no battery gets three
rows rather than a `--` placeholder.

The percentage is computed as `charge_now / charge_full`, **not** read from the
kernel's `capacity` attribute. Not every driver defines `capacity` the same way:
the SBS driver on Apple laptops divides by `charge_full_**design**`, so on a worn
cell it reads far lower than anything else on the system — 54% against upower's
78% on this machine, a battery at 68% health after 518 cycles. `now/full` is the
charge as a fraction of what the cell holds *today*, which is what upower, GNOME
and the Quickshell bar all show, so the lock screen now agrees with the bar.
Drivers expose either `charge_*` (µAh) or `energy_*` (µWh); both are tried, with
`capacity` as a last resort. Both new options default to `""`, in which
case the new branch is skipped and rendering is identical to stock. Drop the
`overrideAttrs` and the two flags if you would rather not carry a patch; you get
the stock two-line clock.

The glyph table is shared with the bar on purpose. Both draw the same Material
Design cells — `nf-md-battery_outline` under 10%, `nf-md-battery_10`…`_90` for
the tenths in between, `nf-md-battery` at full and `nf-md-battery_charging`
while on mains — so locking the screen does not change the picture you were
just looking at. If you change one, change the other: the table is in
`battext()` in the patch and in the battery `IconCell` in `shell.qml`. The one
thing that does *not* carry across is colour — the bar turns peach under 20% and
red under 10%, while swaylock draws the whole battery line in `--text-color` and
has no per-line colour option.

**`--ignore-empty-password` fixes a real bug, not a cosmetic one.** swayidle
blanks the panel 30s after locking, and the natural way to wake it is to tap
Enter — which reaches the still-running swaylock, submits an empty password, and
paints **"Wrong!"** before you have typed a character. The journal showed this
cleanly: an auth failure on the first attempt after every *idle* lock, and none
at all after a manual `Super+Ctrl+Q` lock, where nothing needed waking. The flag
just declines to submit an empty buffer. It only covers Enter; waking with a
*letter* key still drops that letter into the buffer, and swaylock has no option
for that. Wake with the trackpad and no keystroke is generated at all.

**`mem_sleep_default=s2idle` is a suspend fix with a battery cost.** The kernel
defaults to `deep` (ACPI S3) on this machine, and `deep` does not reliably
resume: the journal reaches `PM: suspend entry (deep)` and then writes nothing
more, with the next line being a cold boot — a firmware hang that needs the
power button held. s2idle resumes every time, but idle drain goes from roughly
1–2%/hour to 5–10%/hour. Test the default without rebuilding via
`echo deep | sudo tee /sys/power/mem_sleep`.

**swayidle locks before it blanks** — lock at 300s, monitor off at 330s. The
wallpaper is deliberately visible for 30 seconds before the backlight dies.

**Quickshell's `shell.qml` lives outside the Nix store on purpose,** as a real
writable file, so Quickshell hot-reloads edits instead of needing a rebuild.

**Screen recording bypasses xdg-desktop-portal entirely.** Every portal-based
recorder — Kooha, OBS's built-in capture, GNOME's — fails under niri on this
machine, and the failure looks like a bug in the recorder: *"Failed to
initialize pipeline state to playing / Element failed to change its state"*. It
is neither side's bug. niri offers screencast buffers as DMA-BUF only (a single
format, `BGRx`, carrying a mandatory `Format:Video:modifier` property), while
GStreamer's `pipewiresrc` advertises 34 system-memory formats and no modifiers.
The two sets do not intersect, so PipeWire kills the link with `no more input
formats` before the first frame moves. Nothing in this repo can reach that —
it is upstream code on both sides.

`wf-recorder` avoids the problem by not using the portal at all: it speaks
`zwlr_screencopy_manager_v1` directly to niri, which is the same protocol `grim`
uses for the screenshot binds, already proven working here. If you ever want a
GUI recorder back, check whether `pipewiresrc` has learned to negotiate
modifiers first — otherwise it will fail exactly the same way.

**Idle auto-suspend is off, because the SSD does not survive suspend.** Worth
reading before turning it back on, and worth reading for the diagnosis, which
went through two wrong answers first.

The symptom was reported as a lock-screen problem: *"the screen goes off, then
my password is always wrong and the only way back is a reboot."* That points
squarely at swaylock and PAM. Both are innocent — but so was the second answer,
that the machine never resumed at all. It does resume. The kernel runs, niri
redraws, the lock screen accepts keystrokes. What does not come back is the
disk.

The proof is in what the journal does *not* contain. Every suspend is the last
line of its boot; there is no entry of any kind afterwards. That looks like a
dead kernel until you notice NetBird logs about forty lines a minute during
normal operation, and the failure window is minutes long while someone retypes
a password. Hundreds of missing lines, from a process that is demonstrably still
running. journald was alive and simply could not write. Everything else follows:
PAM has to exec `unix_chkpwd` out of `/nix/store` and read `/etc/shadow`, so with
no storage every password is "wrong" no matter what is typed, and nothing new
can be exec'd, so rebooting really is the only way out.

The controller is an `APPLE SSD AP0128J` behind PCI `106b:2003` — Apple's own
ANS2. The kernel already treats it as odd, applying `NVME_QUIRK_SINGLE_VECTOR`
(hence `1/0/0 default/read/poll queues` in the boot log). What it does not apply
to this ID is `NVME_QUIRK_SIMPLE_SUSPEND`, and that is the bug. `nvme_suspend()`
only shuts the controller down and does a full reset on resume when the platform
suspends via firmware; under s2idle it does not, so the ANS2 is left in a
host-managed power state it does not survive and returns attached but never
completing I/O. [The same failure is documented on T2
Macs](https://ratatoskr.run/linux-nvme/2026/09/17519939), where the fix is to
add the quirk — and [the MacBookPro14,x notes](https://takachin.github.io/mbp2017-linux-note/en/suspend-resume.html)
describe the same PCIe-switch devices failing with "Unable to change power
state".

Two earlier suspects were tested and cleared, which is why they are named here
rather than re-tried: the sleep state (a hang was recorded under `s2idle` and
under `deep`, identically) and `facetimehd` (it deinitialises immediately before
every hang and leaks memory doing it, but a suspend with the module `rmmod`-ed
first hung anyway).

The current mitigation is three settings that need no patched kernel —
`nvme_core.default_ps_max_latency_us=0` to disable APST, `pcie_aspm=off` because
`nvme_suspend()` also takes the safe shutdown path when ASPM is off on the
device, and an `nvme-no-d3cold` unit holding the NVMe and its root port out of
D3cold. The ASPM reasoning is inferred from the driver's logic rather than
confirmed. If suspend still dies, the definitive fix is patching `106b:2003`
into `nvme_id_table` with `NVME_QUIRK_SIMPLE_SUSPEND`, which costs a full kernel
build on a 2017 dual-core. Re-enable the 900 s timer only once a suspend has
actually been watched to come back.

Closing the lid does not suspend either, for the same reason —
`HandleLidSwitch` and `HandleLidSwitchExternalPower` are both `lock`. Disabling
the idle timer only closed the unattended route into it; shutting the lid still
walked straight in. Note that logind does not lock anything itself when
set to `lock`, it only emits a Lock signal on the session bus, so swayidle needs
a matching `lock` event or the lid does nothing at all — the two have to move
together. The cost is that a closed laptop now stays awake and will run its
battery flat in a bag. That is a deliberate trade against losing the session,
and it reverts to `suspend` along with the 900 s timer once resume is proven.

Two smaller things came out of the same investigation. `lock-screen` now exits
early if a locker is already running: the 300 s timeout and the `before-sleep`
hook both ask to lock, only one client can hold `ext_session_lock_v1`, and the
loser was logging `refusing lock as already locked` / `Failed to daemonize` on
every single idle suspend — harmless, but enough routine noise to bury a real
failure. And the lock screen now passes `--show-failed-attempts` and
`--indicator-caps-lock`, because "it says my password is wrong" had no
observable detail behind it: a stray character from the keypress that woke the
panel, Caps Lock left on, and a modifier stuck across a resume all look
identical on a screen that shows nothing but `Wrong!`. Escape clears the
password buffer, which handles the stray-character case.

**The Bluetooth controller needs a retry at boot, and the picker hides most of
what it finds.** Two unrelated-looking problems, both worth knowing about.

The radio is a Broadcom BCM4350C0 on a UART, not USB. Apple's ACPI tables do not
describe its reset GPIO the way `hci_bcm` expects, so the driver cannot reset the
chip before talking to it and every boot logs `No reset resource, using default
baud rate`. Usually the baud-rate command fails instantly with `-16` (EBUSY) and
the driver carries on regardless; about one boot in five the chip does not answer
at all, the command times out with `-110`, and setup aborts. The trap is what
that looks like afterwards: `bluetoothd` is running and healthy,
`/sys/class/bluetooth/hci0` exists and looks normal, but no adapter is ever
published on D-Bus. `bluetoothctl list` prints nothing and the bar reads *"bluez
not running"* — which is the one thing that is definitely not wrong.
`bluetooth-uart-recover` checks D-Bus (not sysfs, which lies here) after
`bluetooth.service`, reloads `hci_uart` if no adapter turned up, and powers the
adapter on afterwards. To recover by hand:
`sudo rfkill unblock bluetooth && sudo modprobe -r hci_uart && sudo modprobe hci_uart`.

Separately, the picker deliberately shows a small fraction of what a scan
returns. A scan from a flat picks up around sixty devices, of which roughly eight
ever say what they are; the rest are BLE privacy beacons — phones, watches, tags
— advertising randomised addresses that rotate every few minutes. BlueZ still
creates a device for each and fills `Alias` with the MAC in dashes because there
is nothing else to put there, which is where rows like `62-C8-07-D8-6F-DA` came
from. None of them are pairable. The list therefore keeps anything paired,
bonded, trusted, connected or mid-pairing, plus discovery results that published
a real `Name`, and collapses those by name — a single conference remote was
advertising from four addresses at once and filling four identical rows. The
count of what was held back is printed next to the scan row, so an empty result
reads as *"nothing here is announcing itself"* rather than *"the radio is
broken"*.

**NetBird runs unhardened.** Hardened mode uses `ProtectSystem = "strict"`
(read-only `/etc`) and its DNS integration assumes systemd-resolved. This system
uses openresolv, which needs to write `/etc/resolv.conf`. If you run
systemd-resolved, switch it to `hardened = true` and add your user to the
`netbird` group.

---

## Security note

No credentials are in this repository. Before publishing your own fork, be aware
that `~/.config/netbird/` holds account state including **your email address**,
and `/var/lib/netbird/` holds the peer private key. Neither is included here, and
`.gitignore` excludes them.
