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
| **Quickshell** | The top bar — clock, battery, CPU/mem/disk, wifi, bluetooth, audio, clipboard history. Written from scratch in `config/quickshell/shell.qml`. |
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
| **grim + slurp + satty** | Region select → screenshot → annotate. |
| **kooha** | Screen recording. |
| **ffmpeg-full** | Full ffmpeg with every codec and filter enabled. |
| **playerctl** | Media keys (play/pause/next) against MPRIS. |
| **wl-clipboard + cliphist + wl-clip-persist** | Clipboard, searchable clipboard history, and clipboard survival after the source app closes. |

### System services

| | |
| --- | --- |
| **PipeWire** (+ ALSA, PulseAudio, rtkit) | Audio stack. |
| **BlueZ + blueman** | Bluetooth, with the applet autostarted. |
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

```bash
git clone https://github.com/guohai/my-dotfiles ~/my-dotfiles
cd ~/my-dotfiles
```

**1. Generate your own hardware config** (do not skip this):

```bash
sudo nixos-generate-config
```

`configuration.nix` imports `./hardware-configuration.nix`, which is not in this
repo on purpose. If you skip this step the very first build fails with:

```
error: path '.../hardware-configuration.nix' does not exist
```

That is expected, not a broken repo. `nixos-generate-config` writes the file to
`/etc/nixos/`, which is where step 3 puts everything else.

**2. Read the portability header** at the top of `nixos/configuration.nix` and
edit what applies to you. Every machine-specific line is also marked inline:

```bash
grep -n 'PORTABILITY:' nixos/configuration.nix
```

At minimum you will want to change the **username** (it is `brent` in this repo),
the **timezone**, and delete the **FaceTime HD camera** block unless you are also
on an Intel Mac.

**3. Install:**

```bash
# Everything under nixos/pkgs/ is referenced by configuration.nix as a
# relative path. Copy the whole directory -- missing any one file is an
# eval error before the build even starts, e.g.
#   error: path '/etc/nixos/pkgs/swaylock-effects-weekday.patch' does not exist
sudo mkdir -p /etc/nixos/pkgs
sudo cp nixos/configuration.nix /etc/nixos/configuration.nix
sudo cp nixos/pkgs/*            /etc/nixos/pkgs/

# These three are NOT deployed by configuration.nix -- it does not manage
# them, by design (see "Quickshell's shell.qml lives outside the Nix store"
# below). Skip this and you get a working system with no bar, no keybinds
# and no Mac key layer.
mkdir -p ~/.config/niri ~/.config/quickshell ~/.config/xremap
cp config/niri/config.kdl      ~/.config/niri/
cp config/quickshell/shell.qml ~/.config/quickshell/
cp config/xremap/config.yml    ~/.config/xremap/

sudo nixos-rebuild switch

# The account is created without a password. Set one before logging out, or
# greetd will not let you in.
sudo passwd YOURNAME
```

**4. Log out and back in.** The `input` and `uinput` group memberships, the new
user services, and the session environment variables only take effect on a
fresh session. If you kept the camera block, you need a full **reboot** instead
(it loads a new kernel module).

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
