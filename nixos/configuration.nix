# Edit this configuration file to define what should be installed on
# your system. Help is available in the configuration.nix(5) man page, on
# https://search.nixos.org/options and in the NixOS manual (`nixos-help`).
#
# ============================================================================
# PORTABILITY -- read this first if you are restoring on another machine
# ============================================================================
# This config was written for a MacBookPro14,1 (13-inch Intel, 2017) running
# niri on Wayland. Most of it is hardware-agnostic, but the items below are
# NOT. Each site is also marked inline with `PORTABILITY:` so you can find
# them with:  grep -n 'PORTABILITY:' configuration.nix
#
# MUST change on other hardware:
#   * hardware-configuration.nix -- NOT shipped with these dotfiles on purpose.
#     It contains this laptop's filesystem UUIDs. Generate your own with
#     `nixos-generate-config` and never copy someone else's.
#   * hardware.facetimehd.*  -- Apple Intel Macs ONLY. It builds an out-of-tree
#     kernel module for the Broadcom 1570 PCIe camera (PCI 14e4:1570). On any
#     non-Apple machine this is useless at best. Delete it; a normal USB webcam
#     needs no configuration at all.
#   * boot.loader.systemd-boot -- assumes UEFI. A BIOS/legacy machine needs
#     boot.loader.grub instead.
#
# SHOULD review:
#   * time.timeZone -- set to America/Los_Angeles.
#   * console.font = "ter-v32n" -- a 32px console font, chosen because this is
#     a HiDPI/retina panel. On a 1080p screen it is comically large; try
#     "ter-v16n" or drop the console block entirely.
#   * The username is `lab`, in users.users.lab and home-manager.users.lab.
#     Rename BOTH or home-manager will silently configure nobody.
#   * Apple keyboards have no separate Super/Cmd distinction the way PC
#     keyboards do. The Mac-style key remapping (see the xremap section) maps
#     the Super/Windows key to Cmd, which is what you want on a PC keyboard
#     too, but the muscle memory it targets is macOS'.
#
# Safe everywhere: the niri/Quickshell desktop, terminals, fish, Zed, mpv,
# lock screen, audio/bluetooth/wifi pickers, NetBird, sshd.
# ============================================================================

{ config, lib, pkgs, ... }:

let
  # home-manager pinned by commit rather than pulled from a channel, so the
  # version lives in this file and rebuilds are reproducible.
  #
  # This URL names a *commit*, not a branch, and that is the whole point. It
  # used to be .../archive/release-26.05.tar.gz with a sha256 beside it, which
  # looks pinned but is not: the hash pins the content while the URL keeps
  # moving, so the two silently disagree the moment upstream pushes to the
  # branch. That is not a hypothetical -- it broke a rebuild on 2026-09-13,
  # the day after ec17201 landed, with
  #
  #   error: hash mismatch in file downloaded from
  #     'https://github.com/.../archive/release-26.05.tar.gz'
  #     specified: sha256:0fyjh6bv...
  #     got:       sha256:02mrnlir...
  #
  # and it would have kept happening on every upstream push. A commit URL is
  # immutable, so the hash can never go stale on its own -- an upgrade becomes
  # something this file records deliberately instead of something that arrives
  # unannounced and fails the next unrelated rebuild.
  #
  # To upgrade, resolve the branch head and refresh both lines together:
  #   rev=$(curl -sSL https://api.github.com/repos/nix-community/home-manager/commits/release-26.05 \
  #         | grep -m1 '"sha"' | cut -d'"' -f4)
  #   nix-prefetch-url --unpack "https://github.com/nix-community/home-manager/archive/$rev.tar.gz"
  home-manager = builtins.fetchTarball {
    # release-26.05 as of 2026-09-12
    url = "https://github.com/nix-community/home-manager/archive/ec172013fa62135f58fb58dd17ae9651e8f39727.tar.gz";
    sha256 = "02mrnlirg3jxqfgkv3jh8ar9hqiwhwqq9m7n5jv5hq40vjzq2s1d";
  };

  # Desktop wallpaper, pinned by hash so it is part of the system closure
  # rather than a loose file in ~ that a stray `rm` would take out.
  #
  #   Almsee, Upper Austria -- limestone walls of the Totes Gebirge above an
  #   alpine lake, conifer forest, autumn colour. 4987x3325 (~16.6 MP).
  #   (c) Isiwal / Wikimedia Commons, CC BY-SA 4.0
  #   https://commons.wikimedia.org/wiki/File:Almsee_Nordbucht-4224.jpg
  #
  # To swap it: change the url, then run
  #   nix-prefetch-url <url>
  # and paste the hash below. Some alternatives already vetted at >=4K and
  # roughly this aspect ratio:
  #   File:TR_Yedigöller_asv2021-10_img02.jpg      7952x5304 forested valley
  #   File:Sitno_nov_2023.jpg                      7739x5162 golden-hour snow
  #   File:Karst_peaks_mist_..._Vang_Vieng_Laos.jpg 6571x4381 misty karst
  wallpaper = pkgs.fetchurl {
    url = "https://upload.wikimedia.org/wikipedia/commons/7/7d/Almsee_Nordbucht-4224.jpg";
    sha256 = "0i2xjyk279a8vvdljyg44wj8yxd2ns9xxshqy1iwlfl9wjxwp5wm";
  };

  # Lock-screen wallpapers. A set rather than one image, so the lock screen is
  # not the same picture every time -- lockCmd below picks one at random per
  # lock. All three are Basile Morin / Wikimedia Commons, CC BY-SA 4.0.
  #
  # Chosen by eye against thumbnails, not by title, on three criteria that
  # matter for a *lock* screen specifically:
  #   * dark through the middle, because swaylock's indicator ring and any
  #     "wrong password" text sit dead centre in white;
  #   * dusk/blue palette, so the locked state reads as visually distinct from
  #     the bright daytime Almsee desktop wallpaper above;
  #   * mountains and trees, matching the desktop.
  #
  # These are the full-size originals (6264x4176 - 6571x4381, ~8-11 MB each).
  # Originals rather than Wikimedia's downscaled thumbnails on purpose: the
  # originals are immutable, whereas thumbnails can be regenerated with a
  # different encoder and would silently break the pinned hash.
  lockWallpapers = [
    # Mekong and mountains from Mount Phou Si at dusk, Luang Prabang, Laos.
    # Deep blue dusk, town lights below -- the darkest and best of the three.
    (pkgs.fetchurl {
      url = "https://upload.wikimedia.org/wikipedia/commons/9/9c/Mountains_Mekong_river_and_dwellings_seen_from_Mount_Phou_Si_at_dusk_in_Luang_Prabang_Laos.jpg";
      hash = "sha256-3GIqC4UJms0tkh3zqjO/wJD+UgmL7sgVxnPhfEwv65Q=";
    })
    # Paddy field reflecting pink dusk cloud, mountains behind, Vang Vieng.
    (pkgs.fetchurl {
      url = "https://upload.wikimedia.org/wikipedia/commons/b/b6/Colorful_sky_with_pink_clouds_reflecting_in_the_water_of_a_paddy_field_and_mountains_at_dusk_Vang_Vieng_Laos.jpg";
      hash = "sha256-aQlCZNeK2tkETl9iExlQzpRqYs+uH1tTY8Q+Y2a1MGE=";
    })
    # Karst peaks above a sea of mist at sunrise, Mount Nam Xay, Vang Vieng.
    (pkgs.fetchurl {
      url = "https://upload.wikimedia.org/wikipedia/commons/d/d6/Karst_peaks_mist_and_colorful_clouds_at_sunrise_seen_from_Mount_Nam_Xay_in_Vang_Vieng_Laos.jpg";
      hash = "sha256-VFDKYcpVIcLCY+fF6ecJ/y05wTApT59pf+rs+F9PZws=";
    })
  ];

  # PORTABILITY: panel resolution. Only used to pre-size the lock wallpapers.
  # Get yours from `niri msg outputs`. Too small and the lock screen is soft;
  # too large and you are paying decode time for pixels nobody sees.
  lockWallpaperGeometry = "2560x1600";

  # Blur the lock wallpapers at BUILD time rather than at lock time.
  #
  # This is a latency fix, not a cosmetic one. swaylock-effects applies effects
  # to every image *before* it requests ext_session_lock_v1 -- the ordering is
  # deliberate and commented as such in its main.c, since the alternative is a
  # blank screen while the blur runs. The cost is that nothing at all happens
  # for as long as the blur takes, and these originals are 26-29 megapixels:
  # measured on this machine, ~270ms to decode plus ~1.2s to blur, on four
  # idle cores. Every lock had a dead second and a half in front of it.
  #
  # Worse, that second and a half is spent with the desktop still on screen
  # and still accepting input -- the session is not actually locked until the
  # blur finishes.
  #
  # So: scale to the panel and blur once, at build time, into the store. At
  # lock time swaylock decodes one small pre-blurred JPEG and locks straight
  # away. The `--effect-blur` flag is gone from the lock command as a result.
  #
  # On the radius. swaylock calls apply_effects with scale hardcoded to 1, so
  # `--effect-blur 6x3` was three box passes of radius 6 on the *original*,
  # which cairo then scaled down to the panel -- an effective on-screen radius
  # of 6 * 2560/6264 = 2.45. Three box passes of radius r approximate a
  # Gaussian of variance 3*((2r+1)^2-1)/12, so sigma = 2.9. Hence -blur 0x2.9
  # applied at panel size. Turn that number up if you want it softer; it is
  # now a plain Gaussian sigma in pixels, which is easier to reason about than
  # radius-times-passes.
  #
  # JPEG rather than PNG on purpose: blurred images have almost no high
  # frequency content, so they compress to a couple of hundred KB and decode
  # in tens of milliseconds. -strip drops the EXIF, which is dead weight here.
  preblur = src:
    pkgs.runCommand "lock-wallpaper-blurred.jpg"
      { nativeBuildInputs = [ pkgs.imagemagick ]; }
      ''
        magick ${src} \
          -resize ${lockWallpaperGeometry}^ \
          -gravity center \
          -extent ${lockWallpaperGeometry} \
          -blur 0x2.9 \
          -strip \
          -quality 92 \
          JPEG:$out
      '';

  lockWallpapersBlurred = map preblur lockWallpapers;

  # swaylock-effects rather than plain swaylock. Upstream swaylock can set a
  # background image and nothing else; the -effects fork adds the parts that
  # make it look like a real lock screen -- a clock, a fade-in, blur and
  # vignette over the image. PAM is unaffected: the binary is still named
  # `swaylock`, and /etc/pam.d/swaylock comes from programs.niri.enable pulling
  # in wayland-session.nix, so authentication works either way.
  #
  # Patched to add --weekstr and --batstr. Stock swaylock-effects has two
  # text slots -- a big line (--timestr) and a small line under it (--datestr)
  # -- both drawn with cairo_show_text(), which ignores "\n". So a weekday on
  # its own line above the clock is not reachable from configuration alone.
  # The patch adds a third slot and a render branch that stacks small/big/small
  # using font metrics, so the spacing survives changes to --indicator-radius,
  # --font-size or the font. With --weekstr unset the default is "", the new
  # branch is skipped and rendering is byte-for-byte the stock two-line path.
  #
  # --batstr adds a fourth line on top of the stack for the battery, read
  # straight from /sys/class/power_supply on every frame so it tracks while
  # locked rather than freezing at lock time. {p} is the percentage, {icon} a
  # Nerd Font cell that fills up with the charge level (or a bolt when
  # charging). When the stack grows to four lines the whole block is pushed
  # down half a row so it stays centred in the ring. A machine with no battery
  # gets no line at all -- the layout falls back to three rows rather than
  # printing "--".
  swaylockPkg = pkgs.swaylock-effects.overrideAttrs (o: {
    patches = (o.patches or [ ]) ++ [ ./pkgs/swaylock-effects-weekday.patch ];
  });

  # Picks one wallpaper at random, then execs swaylock with it.
  #
  # A script rather than a static `image=` in swaylock's config file because
  # the config file is read once and cannot express "choose per invocation".
  # Everything that locks the screen goes through this one script: the niri
  # keybind, the swayidle timeout, and the before-sleep hook -- so all three
  # look identical.
  #
  # --ignore-empty-password is not cosmetic, it fixes a real bug. swayidle
  # blanks the panel 30s after locking, and the natural way to wake it is to
  # tap Enter. That Enter reaches the already-running swaylock, which submits
  # an empty password, PAM rejects it, and the screen shows "Wrong!" before
  # you have typed a single character. The journal showed exactly this: an
  # auth failure on the first attempt after every *idle* lock, and none at all
  # after a manual Super+Ctrl+Q lock, where nothing needs waking. With the flag
  # an empty buffer is simply not submitted.
  #
  # Note this only covers Enter. Waking with a letter key still drops that
  # letter into the password buffer -- swaylock has no option for that. Wake
  # the screen with the trackpad and no keystroke is generated at all.
  lockCmd = pkgs.writeShellScriptBin "lock-screen" ''
    set -u

    # Never stack a second locker on a running one. Two paths ask to lock in
    # quick succession: the 300s idle timeout, and then the before-sleep hook
    # when something suspends the machine. Only one client can hold
    # ext_session_lock_v1, so the second swaylock is refused by niri
    # ("refusing lock as already locked with an active client"), exits 2, and
    # this wrapper then reports "Failed to daemonize".
    #
    # That made before-sleep fail on the entire common path -- every journal
    # from an idle suspend ended with those three lines. It is harmless on its
    # own, since the first locker is still up and doing its job, but it means
    # the one hook whose whole purpose is to guarantee a locked screen before
    # sleep was reporting failure routinely, which would bury a genuine
    # failure in noise. Exiting 0 when a locker already owns the session is
    # the correct answer to "make sure the screen is locked".
    #
    # That intent was right; the old implementation of it was not. This used to
    # open with a `pgrep -x swaylock && exit 0` pre-flight check, which asks
    # "is a swaylock process alive?" -- a different question from "is the
    # session already locked?". A live swaylock is in one of three states:
    # holding the lock, still starting up, or exiting after an unlock. Only the
    # first makes `exit 0` correct. In the other two the wrapper reported
    # success to swayidle's before-sleep without anything ever locking,
    # swayidle then released logind's sleep inhibitor, and the machine
    # suspended with the desktop still on screen. The journal caught one: lid
    # closed 08:37:11, no "locking session" line at all, lid reopened 5.7s
    # later onto a live unlocked session.
    #
    # So ask the compositor instead of guessing from a process name. niri
    # refusing the lock IS the authoritative "already locked" answer, and
    # swaylock surfaces it with a known message and a non-zero exit -- both
    # handled at the bottom of this script. Same quiet logs, no false success.

    images=(${lib.concatStringsSep " " (map (w: "${w}") lockWallpapersBlurred)})
    # $RANDOM is bash's, and this script runs under bash via writeShellScriptBin.
    pick="''${images[$((RANDOM % ''${#images[@]}))]}"

    # Absolute paths throughout the rest of this script, never bare `date`,
    # `mktemp`, `cat`, `grep`. swayidle invokes this wrapper with a PATH of one
    # single entry -- bash-interactive/bin -- with no coreutils on it at all.
    # A bare builtin-shadowed name fails with "command not found" on stderr and
    # nothing else, which is how `rm` in kbd-backlight-inhibit stayed broken
    # through every lid cycle without anyone noticing.
    log() {
      printf '%s lock-screen: %s\n' \
        "$(${pkgs.coreutils}/bin/date '+%H:%M:%S.%3N')" "$1" >&2
    }

    # Timestamps, because the interesting failures here are latency failures.
    # Measured locks have taken anywhere from 0.24s to 7.78s between this
    # script starting and niri logging "locking session". That matters beyond
    # tidiness: `-f` returns once the lock is *acquired*, not once swaylock has
    # *painted*, so a slow lock lets the machine suspend while the pre-lock
    # desktop is still the last frame scanned out -- and that stale frame is
    # what the panel shows on resume until swaylock finally draws. Without
    # these two lines that is only diagnosable by correlating niri's log
    # against systemd-logind's by hand.
    log "launching swaylock"

    # swaylock's stderr is captured rather than inherited so the bottom of this
    # script can tell a refusal apart from a real failure. Trade-off, worth
    # knowing: with -f (swayidle's three call sites) swaylock daemonizes
    # immediately and this costs nothing, but the Super+Ctrl+Q keybind passes
    # no -f, so there swaylock blocks and its stderr reaches the journal at
    # unlock rather than live. Nothing is lost by that -- swaylock is silent in
    # a normal session, and failed password attempts are logged by PAM
    # ("pam_unix(swaylock:auth): authentication failure"), a separate channel
    # this does not touch.
    err=$(${pkgs.coreutils}/bin/mktemp)
    trap '${pkgs.coreutils}/bin/rm -f "$err"' EXIT

    status=0

    # No --effect-blur: these images are already blurred, in the store, at
    # panel resolution. See the `preblur` comment above for why.
    #
    # --fade-in is down from 0.4 to 0.15. With the blur precomputed it was the
    # last thing between the keypress and a readable clock. Put it back, or
    # drop the flag, to taste.
    #
    # --show-failed-attempts and --indicator-caps-lock are diagnostics, and
    # they are here because their absence made a support question unanswerable.
    # "It says my password is wrong" has several causes that look identical on
    # a lock screen with no feedback: a stray character from the keypress that
    # woke the panel, Caps Lock left on, or a modifier stuck across a resume.
    # Without a counter you cannot tell one failed attempt from six, and
    # without the Caps Lock indicator the single most common cause is
    # completely invisible. Both are free.
    #
    # Escape clears the password buffer, which is the fix for the stray-letter
    # case -- worth knowing, since nothing on screen says so.
    #
    # Do NOT put comments between the flags below. Every line here ends in a
    # backslash, so a `#` does not start a comment on its own line -- it eats
    # the rest of the joined line and terminates the command early. Doing that
    # silently drops every flag after it, and swaylock still exits 0, so the
    # status check below will not catch it either: you just get a lock screen
    # with the wrong colours.
    ${swaylockPkg}/bin/swaylock \
      --image "$pick" \
      --scaling fill \
      --effect-vignette 0.4:0.4 \
      --ignore-empty-password \
      --clock \
      --weekstr '%a' \
      --timestr '%H:%M' \
      --datestr '%-d %b' \
      --batstr '{icon} {p}%' \
      --show-failed-attempts \
      --indicator-caps-lock \
      --font 'JetBrainsMono Nerd Font' \
      --indicator \
      --indicator-radius 100 \
      --indicator-thickness 8 \
      --fade-in 0.15 \
      --ring-color 89b4fa \
      --key-hl-color a6e3a1 \
      --bs-hl-color f38ba8 \
      --ring-ver-color f9e2af \
      --ring-wrong-color f38ba8 \
      --inside-color 1e1e2e88 \
      --inside-ver-color 1e1e2e88 \
      --inside-wrong-color 1e1e2e88 \
      --text-color cdd6f4 \
      --text-ver-color cdd6f4 \
      --text-wrong-color f38ba8 \
      --line-color 00000000 \
      --separator-color 00000000 \
      "$@" 2>"$err" || status=$?

    if [ "$status" -eq 0 ]; then
      if [ -s "$err" ]; then ${pkgs.coreutils}/bin/cat "$err" >&2; fi
      log "swaylock exited 0"
      exit 0
    fi

    # A locker already owns the session. That is not a failure of "make sure
    # the screen is locked" -- it is already true -- so report success, and
    # deliberately do NOT echo $err while doing it. This message is precisely
    # the routine before-sleep noise the old pgrep pre-check existed to
    # suppress, and it is expected on the common path.
    #
    # Two distinct messages mean this, and swaylock picks between them by how
    # far it got before the compositor said no:
    #   "Failed to lock session -- is another lockscreen running?"
    #   "Exiting - failed to inhibit input: is another lockscreen already running?"
    # Both were read out of the swaylock-effects 1.7.0.0 binary, so the pattern
    # below is matched against the real strings rather than a guess. If a
    # future swaylock reworks its wording this stops recognising a refusal and
    # starts reporting it as a genuine failure -- noisy, but it fails loud
    # rather than silently claiming a lock that never happened, which is the
    # direction this whole change is meant to err in.
    if ${pkgs.gnugrep}/bin/grep -qE "another lockscreen (already )?running" "$err"; then
      log "session already locked by another client, nothing to do"
      exit 0
    fi

    # Anything else is real. Surface it and propagate the status, so a lock
    # that genuinely could not happen is visible to swayidle instead of being
    # rounded up to success.
    if [ -s "$err" ]; then ${pkgs.coreutils}/bin/cat "$err" >&2; fi
    log "swaylock FAILED with status $status -- session may be unlocked"
    exit "$status"
  '';

  # Bring the panel back and hand the keyboard back to the light sensor.
  #
  # This exists because the obvious one-liner was wrong. The swayidle resume
  # hook used to be, literally:
  #
  #   niri msg action power-on-monitors; kbd-backlight-inhibit off
  #
  # and `;` runs the second command whatever the first one did. Right after a
  # resume the compositor is not always answering on its socket yet -- the
  # applespi rebind tears down and recreates the keyboard and touchpad about
  # 2.5s in, and `niri msg` during that window can fail or land on nothing. So
  # the power-on silently did not happen, the inhibit clear did, and the
  # machine came back with a dark screen and a lit keyboard. That exact pair
  # is the symptom that sent me looking.
  #
  # The recovery was worse than the fault. swayidle fires a `resume` command
  # only on an idle -> active edge, and that edge had just been spent. Nothing
  # would retry until the 330s blank timer fired again and the user touched
  # the trackpad a second time -- so the screen stayed black for five and a
  # half minutes, which is precisely the "several minutes" in the report.
  #
  # Hence: retry the power-on until it takes, and only then release the
  # keyboard. Ordering is deliberate -- if the screen cannot be revived, the
  # keyboard stays dark rather than lighting up under a black panel and
  # advertising that something is broken.
  wakeDisplays = pkgs.writeShellScriptBin "wake-displays" ''
    set -u

    # ~5s of trying, which comfortably covers the applespi rebind window.
    # Each attempt is cheap and idempotent: powering on an already-on output
    # is a no-op, so over-calling costs nothing and under-calling costs the
    # five-minute blackout described above.
    i=0
    while [ "$i" -lt 25 ]; do
      if ${pkgs.niri}/bin/niri msg action power-on-monitors 2>/dev/null; then
        break
      fi
      i=$((i + 1))
      # Absolute path: swayidle's PATH is bash-interactive/bin and nothing
      # else, so bare `sleep` is not found. That would not have thrown an
      # error loud enough to notice -- the loop would just spin 25 times in
      # microseconds and give up instantly, turning a 5s retry window into no
      # retry at all. See the identical fix in kbd-backlight-inhibit.
      ${pkgs.coreutils}/bin/sleep 0.2
    done

    # Cleared unconditionally on the way out. If niri never answered, the
    # screen is a lost cause for this cycle, but leaving a stale inhibit file
    # behind would wedge the keyboard dark until the next blank/wake cycle --
    # trading one stuck state for another.
    /run/current-system/sw/bin/kbd-backlight-inhibit off || true
  '';

  # One command behind both recording binds (config.kdl Super+Shift+5 and
  # Super+Ctrl+Shift+5). It is a *toggle*: the same chord that starts a
  # recording stops it, so there is nothing to remember and no second key to
  # learn.
  #
  #   screen-record                -- focused output, with system audio
  #   screen-record region         -- drag a box with slurp first
  #   screen-record full   mute    -- no audio
  #   screen-record region mute
  #
  # Only the first two are bound to keys; `mute` is there for the shell.
  #
  # Why wf-recorder and not kooha, which used to be on this bind: kooha records
  # through xdg-desktop-portal -> PipeWire, and that path is broken under niri
  # on this machine. niri offers screencast buffers as DMA-BUF only (one
  # format, BGRx, with a mandatory Format:Video:modifier property); kooha's
  # pipewiresrc advertises 34 system-memory formats and no modifiers. The two
  # sets do not intersect, so the link dies with "no more input formats" before
  # a single frame moves and GStreamer never reaches PLAYING. That is upstream
  # code on both sides, not anything configurable here.
  #
  # wf-recorder sidesteps the whole portal stack: it speaks
  # zwlr_screencopy_manager_v1 straight to niri -- the same protocol grim
  # already uses for the screenshot binds above, which is why this was the safe
  # bet. It consumes niri's DMA-BUF buffers happily ("enabled DMA-BUF capture"
  # in its own log), which is precisely what kooha could not do.
  recordCmd = pkgs.writeShellScriptBin "screen-record" ''
    set -u
    export PATH=${
      lib.makeBinPath [
        pkgs.wf-recorder
        pkgs.slurp
        pkgs.libnotify
        pkgs.wl-clipboard
        pkgs.niri
        pkgs.procps
        pkgs.coreutils
        pkgs.gnused
      ]
    }

    # Where the in-progress filename is parked so the stop branch, which is a
    # completely separate invocation of this script, can name the file it just
    # finished. Falls back to /tmp only if the session has no runtime dir.
    state="''${XDG_RUNTIME_DIR:-/tmp}/screen-record.path"

    # --- Stop branch -------------------------------------------------------
    # pkill's exit status doubles as "was anything recording?", so this is both
    # the test and the action. Either bind lands here, which is what makes the
    # toggle work regardless of which one started the recording.
    #
    # SIGINT, not the default SIGTERM: wf-recorder traps INT to flush the
    # encoder and write the MP4 moov atom. Killed with TERM you get a file with
    # no index -- unseekable, and most players refuse to open it at all.
    if pkill -INT -x wf-recorder 2>/dev/null; then
      # Wait for the flush instead of racing it, or the size check below reads
      # the file before the index is written. Five seconds is far more than a
      # local encoder needs; it exists so a wedged process cannot hang the bind.
      for _ in $(seq 1 50); do
        pgrep -x wf-recorder >/dev/null || break
        sleep 0.1
      done

      out=$(cat "$state" 2>/dev/null || true)
      rm -f "$state"

      if [ -n "$out" ] && [ -s "$out" ]; then
        # The path, not the video, goes to the clipboard: it is what you
        # actually want next (paste into a chat box, an upload dialog, mpv).
        printf '%s' "$out" | wl-copy
        notify-send -a screen-record -i video-x-generic \
          "Recording saved" "$(basename "$out") -- path copied to clipboard"
      else
        notify-send -a screen-record -u critical \
          "Recording failed" "wf-recorder stopped without writing a file."
      fi
      exit 0
    fi

    # --- Start branch ------------------------------------------------------
    mkdir -p ~/Videos
    out=~/Videos/"Screen Recording $(date '+%Y-%m-%d %H-%M-%S').mp4"

    case "''${1:-full}" in
      region)
        # slurp writes "X,Y WxH", which is exactly what -g expects. Cancelling
        # with Escape makes it exit non-zero, and that must abort quietly --
        # otherwise pressing Escape would start a full-screen recording, which
        # is the opposite of what the user just asked for.
        geom=$(slurp) || exit 0
        [ -n "$geom" ] || exit 0
        target=(-g "$geom")
        label="region"
        ;;
      *)
        # The focused output, not "the only output" -- with an external display
        # attached wf-recorder cannot guess, and records the wrong screen or
        # refuses outright. Parsed with sed rather than jq to avoid pulling jq
        # in for one field; `name` is the only key by that spelling in this
        # object (the others are make/model/serial), so the greedy match is
        # unambiguous.
        name=$(niri msg --json focused-output |
          sed -n 's/.*"name":"\([^"]*\)".*/\1/p')
        [ -n "$name" ] || {
          notify-send -a screen-record -u critical \
            "Recording failed" "Could not determine the focused output."
          exit 1
        }
        target=(-o "$name")
        label="$name"
        ;;
    esac

    # System audio -- what is coming out of the speakers, not the microphone.
    # A bare `--audio` would record the default *source*, which is the built-in
    # mic; the sound of the machine is the default *sink's* monitor.
    #
    # @DEFAULT_MONITOR@ is resolved by the PulseAudio server (pipewire-pulse
    # here, services.pipewire.pulse.enable below), so this needs no pactl at
    # build or run time and, more usefully, follows the default sink -- plug in
    # headphones or connect a Bluetooth speaker mid-recording and the capture
    # moves with it. Hardcoding alsa_output.pci-....monitor would not.
    #
    # For the microphone instead, or both, this is the flag to change:
    # `--audio=@DEFAULT_SOURCE@` for mic. wf-recorder takes one device only, so
    # mic+system together needs a PipeWire loopback and is out of scope here.
    audio=(--audio=@DEFAULT_MONITOR@)
    sound="sound"
    if [ "''${2:-}" = mute ]; then
      audio=()
      sound="silent"
    fi

    printf '%s' "$out" > "$state"

    # Start, then check it is still alive a beat later. wf-recorder fails by
    # exiting during encoder setup, not by returning an error to the shell, so
    # backgrounding it and looking again is the only honest test.
    try() {
      wf-recorder "$@" "''${target[@]}" -f "$out" >/dev/null 2>&1 &
      sleep 1.5
      pgrep -x wf-recorder >/dev/null
    }

    # Rungs, in order of preference. GPU encode first: this panel is 2560x1600
    # and the CPU is a dual-core i5-7360U, so x264 at full size drops frames and
    # pins both cores. VA-API is not a nicety here.
    #
    # Every rung is a real failure mode seen on this machine, not defensive
    # padding. The GPU rung fails outright if intel-media-driver is missing from
    # hardware.graphics (verified: "Failed to initialise VAAPI connection"), and
    # audio takes the whole process down with it if pipewire-pulse is not up
    # yet -- which is easy to hit when the bind is pressed seconds after login.
    # Losing the sound is a far better outcome than losing the recording.
    if try -c h264_vaapi -d /dev/dri/renderD128 "''${audio[@]}"; then
      enc="GPU, $sound"
    elif try "''${audio[@]}"; then
      enc="CPU, $sound"
    elif [ ''${#audio[@]} -gt 0 ] && try -c h264_vaapi -d /dev/dri/renderD128; then
      enc="GPU, no audio"
    else
      rm -f "$state"
      notify-send -a screen-record -u critical \
        "Recording failed to start" "wf-recorder exited immediately."
      exit 1
    fi

    notify-send -a screen-record -i media-record \
      "Recording $label ($enc)" "Press the same keys again to stop."
  '';

  # xremap built with the `niri` cargo feature (nixpkgs exposes the feature set
  # via withVariant; see pkgs/by-name/xr/xremap/package.nix). The niri variant
  # queries niri's IPC socket for the focused window's app_id, and that per-app
  # awareness is the whole point: a blind Super+C -> Ctrl+C remap would send
  # SIGINT inside a terminal instead of copying.
  xremapNiri = pkgs.xremap.override { withVariant = "niri"; };
in
{
  programs.niri.enable = true;
  programs.nix-ld.enable = true;

  # Required by xremap to synthesise the rewritten key events. Sets up the
  # uinput kernel module, the `uinput` group, and a udev rule granting that
  # group 0660 on /dev/uinput.
  hardware.uinput.enable = true;

  # --- VA-API: hardware video encode and decode ---
  # The GPU here is Iris Plus 650 (Kaby Lake, Gen9.5). Without this block the
  # kernel driver is loaded and the desktop composites fine, but there is no
  # userspace VA-API driver, so every video encode and decode runs on a
  # dual-core i5-7360U in software.
  #
  # What it buys, concretely: `screen-record` encodes 2560x1600 H.264 on the
  # GPU instead of pinning both cores with x264 (its CPU fallback exists, but
  # drops frames at this resolution). Chrome and mpv also pick this up for
  # H.264/HEVC/VP9 playback, which is the difference between a warm laptop and
  # a loud one on a long video.
  #
  # iHD (intel-media-driver) and not i965 (intel-vaapi-driver): Kaby Lake is
  # inside iHD's Broadwell-and-newer range, i965 is the legacy driver and is no
  # longer developed. Verified on this machine -- vainfo reports the iHD driver
  # and a hardware VAEntrypointEncSlice for H.264.
  #
  # LIBVA_DRIVER_NAME is set below in environment.sessionVariables. libva can
  # usually infer it from the DRM device, but pinning it removes a probe that
  # silently falls back to software when it guesses wrong.
  hardware.graphics = {
    enable = true;
    extraPackages = with pkgs; [
      intel-media-driver
      # The `vainfo` binary, for checking any of the above is actually true.
      libva-utils
    ];
  };

  # /dev/i2c-* plus the i2c group and the udev rules that hand the group write
  # access to them. Loads the i2c-dev module, which is not built in.
  #
  # This exists for one reason: external monitor brightness in the bar. Every
  # DisplayPort and HDMI link carries an I2C side channel to the monitor's
  # DDC/CI registers, and each connected display shows up as its own i2c
  # adapter. Setting VCP feature 0x10 on one is what moves its backlight.
  #
  # The buses are not only display links -- the SMBus the SPI keyboard and the
  # sensors hang off enumerates here too. Handing the i2c group raw access to
  # every adapter is broader than the job needs; the narrower alternative is a
  # udev rule matching only i2c adapters whose parent is the i915 card. Left
  # broad here because this is a single-user laptop and ddcutil probes buses to
  # find the displays in the first place, so restricting it to the ones already
  # known to be displays is circular.
  hardware.i2c.enable = true;

  # Runs inside the graphical session because it needs NIRI_SOCKET, which niri
  # publishes into the systemd --user environment when it starts.
  systemd.user.services.xremap = {
    description = "xremap - Mac-style Cmd key remapping for GUI apps";
    partOf = [ "graphical-session.target" ];
    after = [ "graphical-session.target" ];
    wantedBy = [ "graphical-session.target" ];
    serviceConfig = {
      ExecStart = "${xremapNiri}/bin/xremap %h/.config/xremap/config.yml";
      Restart = "on-failure";
      RestartSec = 2;
    };
  };

  # Interactive shell for the lab account. Enabling it here (rather than just
  # adding pkgs.fish to systemPackages) is what registers fish in /etc/shells,
  # sets up $PATH via the NixOS shell init, and links the vendor completions
  # that Nix packages ship under share/fish/vendor_completions.d. Without this
  # option, fish starts but has no completions for installed packages.
  #
  # Chosen over zsh because history autosuggestions, syntax highlighting, and
  # completions generated from man pages are all on by default -- zsh needs
  # zsh-autosuggestions + zsh-syntax-highlighting + compinit to match it.
  # Kept at system level even though home-manager also configures fish: only
  # the NixOS option registers fish in /etc/shells and wires up the vendor
  # completions. home-manager handles the per-user shell config instead.
  programs.fish.enable = true;

  home-manager = {
    # Use the system's pkgs rather than a second, independently-pinned nixpkgs.
    useGlobalPkgs = true;
    # Install user packages into /etc/profiles/per-user/lab.
    useUserPackages = true;
    # Instead of aborting when an unmanaged dotfile is in the way, rename it to
    # <name>.hm-bak. This is what makes the first switch survive the existing
    # hand-written kitty.conf / foot.ini.
    backupFileExtension = "hm-bak";

    users.lab = { ... }: {
      home.stateVersion = "26.05";

      programs.fish = {
        enable = true;
        # Skip the "Welcome to fish" banner on every new tab.
        interactiveShellInit = ''
          set -g fish_greeting
        '';
      };

      programs.kitty = {
        enable = true;
        settings = {
          # Portrait tab bar: a vertical sidebar down the left side.
          tab_bar_edge = "left";
          # Keep the sidebar visible with a single tab (kitty's default is 2).
          tab_bar_min_tabs = 1;
          # Quoted so kitty does not choke on the ":" in the template.
          tab_title_template = ''"{index}: {title}"'';
        };
        # `cmd` is kitty's alias for Super on every platform, so these are
        # Super+<key> here. xremap deliberately skips kitty, so kitty sees the
        # real Super press and plain ctrl+c is never rewritten -- it keeps
        # working as SIGINT.
        keybindings = {
          "cmd+c" = "copy_to_clipboard";
          "cmd+v" = "paste_from_clipboard";
          "cmd+t" = "new_tab";
          "cmd+w" = "close_tab";
          "cmd+up" = "previous_tab";
          "cmd+down" = "next_tab";
          "cmd+1" = "goto_tab 1";
          "cmd+2" = "goto_tab 2";
          "cmd+3" = "goto_tab 3";
          "cmd+4" = "goto_tab 4";
          "cmd+5" = "goto_tab 5";
          "cmd+6" = "goto_tab 6";
          "cmd+7" = "goto_tab 7";
          "cmd+8" = "goto_tab 8";
          "cmd+9" = "goto_tab 9";
        };
      };

      programs.foot = {
        enable = true;
        settings.key-bindings = {
          # foot matches modifier+lowercase letter (foot.ini(5)).
          clipboard-copy = "Control+Shift+c Super+c";
          clipboard-paste = "Control+Shift+v Super+v";
        };
      };

      # --- Wallpaper ---
      # niri draws no wallpaper of its own -- without a daemon the background
      # is flat grey. wpaperd is a layer-shell client, which niri supports.
      services.wpaperd = {
        enable = true;
        settings.default = {
          # Interpolated to force the derivation to its store path string --
          # the TOML generator will not coerce a derivation on its own.
          path = "${wallpaper}";
          # The photo is 3:2 and the panel is 16:10, so the two do not match.
          # "fit" would letterbox; "center" crops ~6% off top and bottom
          # instead, which this composition can afford.
          mode = "center";
        };
      };

      # --- Code editor ---
      # Zed rather than VS Code. Both give syntax highlighting; the difference
      # is what they are. VS Code is Electron -- a Chromium per window, ~400 MB
      # resident on an empty folder, and its highlighting is TextMate regexes
      # (which is why a long line or a nested template literal sometimes colours
      # wrong). Zed is native Rust on the GPU, starts in well under a second,
      # and highlights with tree-sitter: a real incremental parse of the file,
      # so the colours follow the syntax tree rather than a regex guess. That is
      # the "beautiful highlighting" difference, and it is structural, not
      # theming.
      #
      # What is given up: Zed's extension catalogue is far smaller than the VS
      # Code marketplace, and there is no equivalent of the Remote-SSH or
      # devcontainer ecosystem (Zed has its own remoting, but it is not the
      # same thing). For editing the .nix / config files on this laptop, none of
      # that is in play.
      #
      # Binary is `zeditor` on Linux, not `zed` -- `zed` is taken by the ZFS
      # event daemon, so nixpkgs renames it.
      programs.zed-editor = {
        enable = true;

        # Language servers Zed shells out to. Zed does not bundle them and will
        # silently offer no completion if they are not on PATH; putting them
        # here rather than in home.packages keeps them scoped to the editor.
        # nixd over nil: it evaluates the actual nixpkgs, so it can complete
        # option names inside this very file.
        extraPackages = [
          pkgs.nixd
          pkgs.nixfmt
        ];

        # Installed from Zed's own extension registry on first launch. These are
        # the tree-sitter grammars plus LSP glue.
        extensions = [ "nix" "toml" "make" ];

        userSettings = {
          theme = {
            mode = "dark";
            dark = "One Dark";
            light = "One Light";
          };

          # Matches the kitty/foot setup rather than Zed's bundled default.
          buffer_font_family = "JetBrainsMono Nerd Font";
          buffer_font_size = 14;
          ui_font_size = 15;

          # Off by default in Zed, and it phones home on every keystroke
          # otherwise.
          telemetry = {
            diagnostics = false;
            metrics = false;
          };

          # Zed ships an AI panel that is on by default; this hides it rather
          # than leaving a dead button in the corner.
          features.edit_prediction_provider = "none";

          # nixd needs to be told which flake/expression to evaluate. This
          # points it at the system config so option completion works.
          lsp.nixd.settings.formatting.command = [ "nixfmt" ];

          languages.Nix.formatter.external = {
            command = "nixfmt";
            arguments = [ ];
          };
        };

        # mutableUserSettings defaults to true, so the block above is written
        # as a real file that Zed's own settings UI can still edit -- unlike
        # the VS Code module, which would have made it a read-only symlink.

        # Mac keymap. Only the chords xremap does NOT already handle are listed
        # here. xremap rewrites Super+{c,v,x,a,z,s,f,t,w,n,r,l} and Super+arrows
        # to their Ctrl equivalents before Zed sees them -- and Zed's *Linux*
        # default keymap is already Ctrl-based, so Cmd+C/V/X/A/Z/S/F/W/N/T and
        # Cmd+arrow work out of the box with nothing configured. A "super-c"
        # entry here could never fire, because the Super never reaches the app.
        #
        # "super" is Zed's Linux name for the Windows key (it also accepts
        # "cmd" and "win" as aliases -- verified against the binary's own
        # keymap docstring in 1.3.6).
        #
        # Avoided: super-e and super-q, which niri takes globally for nautilus
        # and close-window and so never reach Zed either.
        userKeymaps = [
          {
            context = "Workspace";
            bindings = {
              "super-p" = "file_finder::Toggle";
              "super-shift-p" = "command_palette::Toggle";
              # No "super-shift-f" here on purpose. xremap matches modifiers
              # inexactly (exact_match defaults to false), so Super+Shift+F
              # still matches its `Super-f: C-f` rule and arrives as
              # Ctrl+Shift+F -- which is already Zed's Linux default for
              # project search. Binding it would be dead config. Same trap
              # that killed the old Super+Alt+L lock bind.
              "super-b" = "workspace::ToggleLeftDock";
              "super-j" = "workspace::ToggleBottomDock";
              "super-," = "zed::OpenSettings";
              "super-o" = "workspace::Open";
              "super-\\" = "pane::SplitRight";
              "super-`" = "workspace::NewTerminal";
            };
          }
          {
            context = "Editor";
            bindings = {
              "super-/" = "editor::ToggleComments";
              "super-d" = "editor::SelectNext";
              "super-shift-k" = "editor::DeleteLine";
              "super-enter" = "editor::NewlineBelow";
              "super-shift-enter" = "editor::NewlineAbove";
              "super-]" = "editor::Indent";
              "super-[" = "editor::Outdent";
              "super-shift-o" = "outline::Toggle";
              "super-g" = "search::SelectNextMatch";
              "super-shift-g" = "search::SelectPrevMatch";
            };
          }
        ];
      };

      # --- Video player ---
      # mpv, same as on the Mac. It is also the right answer on NixOS
      # independently of that: it is the only player here that is a native
      # Wayland client with no toolkit baggage (vlc drags in Qt, celluloid is
      # a GTK front end *around* mpv), it hardware-decodes through VAAPI on
      # this Intel GPU, and its config is a flat text file rather than a
      # settings dialog -- which is what makes it declarable here at all.
      programs.mpv = {
        enable = true;

        config = {
          # Hardware decode. "auto-safe" rather than plain "auto": it only
          # enables backends known to be correct for the codec, so a broken
          # VAAPI path falls back to software instead of showing green frames.
          hwdec = "auto-safe";
          # vo=gpu-next is the newer libplacebo renderer -- better scaling and
          # correct HDR tone mapping. gpu is the fallback if a driver chokes.
          vo = "gpu-next";
          # Keep the window from being resized to the video's pixel size on a
          # HiDPI panel, which makes 480p clips postage stamps.
          autofit-larger = "90%x90%";

          # Remember position on quit, so a half-watched film resumes.
          save-position-on-quit = true;

          # Prefer English audio/subs but fall through rather than muting.
          alang = "eng,en,jpn,ja";
          slang = "eng,en";
          # Show subtitles even when the audio is already the preferred
          # language -- mpv otherwise hides them, which is not what macOS
          # players do.
          subs-with-matching-audio = true;

          # No OSD spam on every property change.
          osd-bar = true;
          # Screenshots land next to the wallpaper rather than in $PWD.
          screenshot-directory = "~/Pictures/mpv";
          screenshot-format = "png";
        };

        bindings = {
          # macOS-style: arrow seek in small steps, matching QuickTime.
          RIGHT = "seek 5";
          LEFT = "seek -5";
          UP = "seek 60";
          DOWN = "seek -60";
        };
      };

      # --- Bluetooth pairing agent ---
      # This is the piece that makes "pair" work from the Quickshell bar: the
      # applet registers an org.bluez.Agent1 on the session bus and answers the
      # PIN / "confirm this code" callbacks with a GTK dialog. It also puts a
      # tray icon somewhere no tray exists, which is harmless -- the agent is
      # the reason it runs.
      services.blueman-applet.enable = true;

      # --- Clipboard ---
      # cliphist watches the Wayland selection and keeps a searchable history.
      # Bound to Mod+V in niri (see the note in config.kdl about why not
      # Super+Shift+V).
      services.cliphist.enable = true;

      # Mac parity fix, not a nicety: on Wayland the clipboard lives in the
      # *source* client, so copying in an app and then quitting it leaves you
      # with an empty clipboard. wl-clip-persist takes ownership so the
      # contents outlive the app, which is what macOS does.
      services.wl-clip-persist = {
        enable = true;
        clipboardType = "regular";
      };

      # --- Idle / lock ---
      # niri implements ext_session_lock_manager_v1 and ext_idle_notifier_v1,
      # which is what swaylock and swayidle respectively speak. Nothing was
      # driving them before: the Super+Alt+L bind in niri's config.kdl points
      # at swaylock, but swaylock was never installed, so it did nothing.
      #
      # package is swaylock-effects (see swaylockPkg in the let block) so the
      # lock screen gets a wallpaper, clock, blur and fade-in. Nothing here
      # calls the binary directly -- everything goes through the lock-screen
      # script, which picks one of the wallpapers at random per lock.
      programs.swaylock = {
        enable = true;
        package = swaylockPkg;
      };

      services.swayidle = {
        enable = true;
        timeouts = [
          # Ordering matters and is the whole point: lock at 300s, blank at
          # 330s. The lock screen is therefore already up -- wallpaper, clock
          # and all -- for 30 seconds *before* the panel powers off, so
          # touching the trackpad at 340s wakes to the locked wallpaper rather
          # than to a live desktop that then locks under you.
          #
          # Widen the gap here if 30s feels too brief to actually see it; the
          # only cost is the backlight staying on longer.
          {
            timeout = 300;
            command = "${lockCmd}/bin/lock-screen -f";
          }
          # The keyboard backlight follows the screen. A lit keyboard under a
          # blank panel is never wanted, and the ambient sensor cannot know the
          # difference -- a dark room reads the same whether you are sitting
          # there or gone. So the compositor, which does know, says so.
          #
          # kbd-backlight-inhibit is a flag file under /run that the
          # kbd-backlight-als daemon polls; see hardware-macbookpro14.nix for
          # both ends. Referenced through /run/current-system/sw/bin rather
          # than a store path because it is defined in the other module and
          # there is no clean way to reach its derivation from here -- the
          # profile path is stable and survives rebuilds either way.
          #
          # swayidle hands these to `sh -c`, so the semicolon works. Order
          # matters on the way down only in that it does not: both are
          # instantaneous and neither depends on the other.
          {
            timeout = 330;
            command = "${pkgs.niri}/bin/niri msg action power-off-monitors; /run/current-system/sw/bin/kbd-backlight-inhibit on";
            resumeCommand = "${wakeDisplays}/bin/wake-displays";
          }
          # Auto-suspend at 900s. This was DISABLED for a while, and the story
          # is worth keeping because it explains three other settings in this
          # file.
          #
          # The machine originally never resumed from suspend at all: five
          # `PM: suspend entry (deep)` lines across seven days and not one
          # `PM: suspend exit`. Every one was the last line of its boot. The
          # user-visible shape was "the screen locks and then my password is
          # always wrong, and I have to reboot", which looks like swaylock or
          # PAM. Neither was at fault -- lock at 300s, panel off at 330s,
          # suspend at 900s, and then the machine was simply gone.
          #
          # Three separate defects had to be fixed before this was safe to
          # turn back on:
          #
          #   1. deep/S3 hung outright. `mem_sleep_default=s2idle` (see
          #      boot.kernelParams) switched it to the state this generation of
          #      MacBook actually uses.
          #
          #      Going back to deep is a recurring temptation, because s2idle is
          #      what leaves the Thunderbolt controller wedged and deep would
          #      hand it to firmware to re-initialise. Resist it: this is the
          #      machine that produced five `suspend entry (deep)` lines and
          #      zero exits. If it is ever tried anyway, use
          #      `echo deep | sudo tee /sys/power/mem_sleep` and one manual
          #      suspend rather than rebuilding -- that reverts on power-off,
          #      which matters when the failure mode is a machine you cannot
          #      log into.
          #   2. The Apple ANS2 NVMe controller was not being shut down on the
          #      s2idle path, so the disk came back wedged. See the
          #      nvme-no-d3cold unit further down.
          #   3. Suspend entry itself took 38-79s because the Intel LPSS SPI
          #      controller was runtime-suspending underneath the driver. See
          #      the udev rule in hardware-macbookpro14.nix.
          #
          # If this ever starts losing sessions again, comment this block out
          # first -- it is the only thing that suspends the machine unattended,
          # and having it off costs nothing but battery.
          {
            timeout = 900;
            command = "${pkgs.systemd}/bin/systemctl suspend";
          }
        ];
        # Attrset keyed by event name -- the older list-of-{event,command}
        # form still parses but warns on eval.
        events = {
          # Lock *before* the machine sleeps, not after it wakes -- otherwise
          # the desktop is briefly visible on resume before the locker appears.
          before-sleep = "${lockCmd}/bin/lock-screen -f";

          # The belt to the resume hook's braces, and the more reliable of the
          # two. This fires on logind's PrepareForSleep(false) -- every single
          # resume, unconditionally -- whereas the 330s timer's resumeCommand
          # fires only on an idle -> active edge, and only if that timer had
          # actually elapsed. The failure being fixed here is precisely the
          # case where that edge is spent or never arrives, so relying on it
          # alone is what created the five-minute black screen.
          #
          # Running both is fine: wake-displays is idempotent, and powering on
          # a live output does nothing.
          after-resume = "${wakeDisplays}/bin/wake-displays";

          # logind's Lock signal. logind never locks anything itself -- it just
          # announces the intent on the session bus and expects a listener.
          # This is now reached via `loginctl lock-session` rather than by
          # closing the lid (HandleLidSwitch went back to "suspend", see
          # below), but it is still the only thing wired to that signal, so
          # removing it would make lock-session a no-op.
          lock = "${lockCmd}/bin/lock-screen -f";
        };
      };

      home.packages = [
        # The bar's audio popup shells out to pavucontrol for the per-app mixer.
        # Building a full mixer in QML is possible via Quickshell.Services.
        # Pipewire, but pavucontrol already does it well.
        pkgs.pavucontrol

        # Bluetooth escape hatch, the same role pavucontrol plays for audio:
        # profile/codec switching and anything the bar's picker does not cover.
        # The bar opens it as `kitty --class bluetui -e bluetui`.
        #
        # This replaces blueman-manager, which was the previous escape hatch and
        # is a GTK3 tree view that looks nothing like the rest of the desktop.
        # bluetui is a TUI, so it inherits the terminal palette for free rather
        # than needing to be themed, and it registers a bluez pairing agent of
        # its own -- org.bluez.Agent1, AgentManager1, RegisterAgent and
        # RequestDefaultAgent are all present in the binary, checked the same way
        # the quickshell binary was checked below and found to have none. So a
        # pairing begun inside bluetui is answered inside bluetui.
        #
        # That does not make blueman redundant: bluetui only holds an agent while
        # it is open, and pairing from the bar needs one registered permanently.
        # See services.blueman.enable below.
        pkgs.bluetui

        # Backs the brightness rows in the bar's display picker.
        #
        # An external monitor has no backlight device -- /sys/class/backlight is
        # only ever the internal panel, which is why brightnessctl below can
        # reach eDP-1 and nothing else. The panel on the other end of a
        # DisplayPort cable is adjusted by talking DDC/CI to it over the I2C
        # channel embedded in the link, which is what ddcutil does: VCP feature
        # 0x10 is luminance, so `ddcutil setvcp 10 60` is the whole operation.
        #
        # Needs hardware.i2c.enable below for the /dev/i2c-* nodes and the i2c
        # group, and the user in that group; without both, ddcutil sees no
        # displays and the bar silently falls back to showing nothing for
        # external brightness.
        #
        # Not every monitor answers. DDC is optional and plenty of panels
        # either ignore it or implement it badly, so `ddcutil detect` is the
        # test that matters -- the bar treats a display it cannot find as
        # simply having no brightness control rather than erroring at you.
        pkgs.ddcutil

        # File manager. Chosen over thunar/nemo/dolphin because the GNOME and
        # GTK xdg-desktop-portal backends are already installed (programs.niri.
        # enable pulls them in for screencast and file chooser), so nautilus
        # adds no new toolkit stack -- and it is the closest thing to Finder:
        # GTK4, sidebar of bookmarks, type-ahead search, tabs, split view.
        # Launch with Mod+E (see ~/.config/niri/config.kdl). Its supporting
        # services -- gvfs, udisks2, the open-in-terminal extension -- are
        # enabled at system level above.
        pkgs.nautilus

        # ffmpeg CLI tools: ffmpeg, ffprobe, ffplay.
        #
        # ffmpeg-full rather than plain ffmpeg. The default nixpkgs `ffmpeg` is
        # built small -- no libx264/libx265/libaom encoders, no libass subtitle
        # burn-in, no frei0r filters -- so `ffmpeg -c:v libx264` fails with
        # "Unknown encoder". -full turns those on. It is a much larger closure
        # and takes a while to substitute the first time; that is the cost.
        #
        # Note mpv and wf-recorder already link ffmpeg *libraries*; this adds
        # the command-line binaries, which were not previously installed.
        pkgs.ffmpeg-full

        # The lock-screen wrapper itself, so `lock-screen` is on PATH and the
        # niri keybind can spawn it by name (see ~/.config/niri/config.kdl).
        lockCmd

        # luvus -- TUI that multiplexes several AI coding-agent sessions.
        # Not in nixpkgs yet, so it is built from ./pkgs/luvus.nix, which is
        # upstream's own nix/package.nix with the hashes filled in. See that
        # file for how to bump the version.
        (pkgs.callPackage ./pkgs/luvus.nix { })
      ];

      # https://quickshell.org -- QtQuick desktop shell (bar/panels/widgets).
      programs.quickshell = {
        enable = true;
        # Autostarts from graphical-session.target, the same target niri
        # publishes into and that xremap uses.
        systemd.enable = true;
        # `configs` is deliberately NOT set. Leaving activeConfig null makes
        # quickshell read ~/.config/quickshell/shell.qml directly, as an
        # ordinary writable file rather than a read-only store symlink.
        # Quickshell hot-reloads on save, so editing the bar is instant --
        # putting the QML in the Nix store would turn every tweak into a
        # sudo nixos-rebuild. Move it into `configs` once the shell settles.
      };
    };
  };

  virtualisation.docker = {
    enable = true;
    autoPrune = {
      enable = true;
      dates = "weekly";
    };
  };

  users.users.root.extraGroups = ["docker"];

  # Normal (non-root) desktop account. Chrome and other browsers refuse to run
  # as root without --no-sandbox, so log into niri as this user, not as root.
  # PORTABILITY: the username `lab` is hardcoded here AND in
  # `home-manager.users.lab` further down. Rename BOTH together, or
  # home-manager will happily configure a user that does not exist.
  users.users.lab = {
    isNormalUser = true;
    description = "lab";
    # input  -> read /dev/input/event* (xremap grabs the keyboard)
    # uinput -> write /dev/uinput (xremap emits the rewritten events)
    # i2c    -> write /dev/i2c-* (ddcutil drives external monitor brightness
    #           over DDC/CI; see hardware.i2c.enable below). Adding a group
    #           does not affect an already-running session -- the credentials
    #           were fixed at login -- so this one needs a full logout before
    #           the bar's brightness rows can reach an external panel.
    extraGroups = [ "wheel" "networkmanager" "video" "audio" "docker" "input" "uinput" "i2c" ];
    # fish is not POSIX-compatible (`export X=y` is `set -x X y`, and bash
    # snippets cannot be `source`d). root is deliberately left on bash so
    # there is always a POSIX recovery shell if a fish change goes wrong.
    shell = pkgs.fish;
  };

  nixpkgs.config.allowUnfree = true;

  environment.systemPackages = with pkgs; [
    nodejs
    # Installed system-wide so every account gets it. The old npm -g install
    # lived under /root/.npm-global, which is unreachable from the lab user
    # because /root is mode 0700. Self-update is disabled (read-only Nix
    # store); bump the channel and rebuild to upgrade.
    claude-code
    git
    # ncurses browser for git history. Reads the repo directly, no daemon and
    # no config of its own; `tig` in any working tree is the whole interface.
    tig
    # GitHub CLI: PRs, issues, releases, and `gh auth login` as a git
    # credential helper over HTTPS, which avoids managing a deploy key.
    #
    # Note where its state lands: `gh auth login` writes an OAuth token to
    # ~/.config/gh/hosts.yml in plaintext. That path is outside this repo, but
    # it is worth knowing about before backing up ~/.config wholesale.
    gh
    # Second coding agent alongside claude-code. Same reasoning for putting it
    # system-wide rather than npm -g: the Nix store is read-only, so its
    # self-update is inert and upgrading means bumping the channel and
    # rebuilding. Auth state lands in ~/.codex/, outside this repo.
    codex
    # Editor. Deliberately not wired to $EDITOR here -- nothing in this config
    # sets that, and changing it would silently redirect git, systemctl edit
    # and visudo for every account at once. Set it per-user if wanted.
    neovim
    # For `strings`, plus objdump/nm/readelf. Pulled in after debugging a
    # swaylock issue stalled on `strings` not existing: the invocation had its
    # stderr redirected to /dev/null, so a missing binary looked exactly like a
    # binary with no matching strings in it, and sent the search down a dead
    # end. This is the wrapped binutils, so it also puts ld/as on PATH; that
    # does not affect Nix builds, which run sandboxed without systemPackages.
    # Use binutils-unwrapped instead if the bare linker on PATH is unwanted.
    binutils
    google-chrome
    fuzzel
    wl-clipboard
    mako
    tuigreet
    # Referenced by binds already present in ~/.config/niri/config.kdl that
    # were silently dead because the binaries were never installed:
    #   XF86MonBrightnessUp/Down -> brightnessctl  (config.kdl:402-403)
    #   XF86AudioPlay/Next/Prev  -> playerctl      (config.kdl:394-397)
    brightnessctl
    playerctl
    # Capture stack. niri screenshots natively (Print / Ctrl+Print / Alt+Print,
    # config.kdl:~640) but cannot annotate, so grim+slurp feed satty for the
    # Super+Shift+3/4 binds.
    #
    # All four talk zwlr_screencopy_manager_v1 directly to niri. Nothing here
    # goes through xdg-desktop-portal, which is deliberate: the portal path is
    # what broke kooha (see the recordCmd comment in the let block above).
    grim
    slurp
    satty
    wf-recorder
    # The Super+Shift+5 / Super+Ctrl+Shift+5 toggle. Defined in the let block
    # above; it wraps wf-recorder, slurp and niri msg.
    recordCmd
    # Stays system-level: xremap needs the input/uinput groups and a system
    # udev rule, so managing it per-user would split the config in two.
    xremapNiri
    # kitty, foot and quickshell are NOT here -- home-manager installs them
    # for the lab user alongside their config (see home-manager.users.lab).
  ];

  fonts.packages = with pkgs; [
    nerd-fonts.jetbrains-mono
    noto-fonts-color-emoji
  ];

  environment.sessionVariables = {
    NIXOS_OZONE_WL = "1";
    MOZ_ENABLE_WAYLAND = "1";
    GDK_BACKEND = "wayland";
    QT_QPA_PLATFORM = "wayland";
    QT_WAYLAND_DISABLE_WINDOWDECORATION = "1";
    SDL_VIDEODRIVER = "wayland";
    CLUTTER_BACKEND = "wayland";
    # Pins VA-API to the iHD driver installed by hardware.graphics above. See
    # that block for why iHD rather than i965.
    LIBVA_DRIVER_NAME = "iHD";
  };

  services.greetd = {
    enable = true;
    settings = {
      default_session = {
        # --user lab prefills the login form with the lab account. Do not add
        # --remember: it overwrites the prefill with whoever logged in last
        # (which is how root kept coming back). Press Esc at the password
        # prompt to type a different username.
        command = "${pkgs.tuigreet}/bin/tuigreet --time --user lab --cmd niri-session";
        user = "greeter";
      };
    };
  };

  security.polkit.enable = true;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    pulse.enable = true;
  };

  # --- Daemons behind the Quickshell status modules ---
  # Quickshell only *binds* to these over D-Bus; it does not ship them. Without
  # the daemons the corresponding QML modules load but stay empty.
  #
  # Quickshell.Services.UPower -> battery percentage, charge state, time-to-empty.
  # This machine has BAT0 + ADP1, so there is a real battery to report on.
  services.upower.enable = true;

  # Quickshell.Services.UPower.PowerProfiles -> balanced/performance/power-saver.
  # Mutually exclusive with TLP; TLP is not enabled here.
  services.power-profiles-daemon.enable = true;

  # Intel HWP ("Speed Shift") hands P-state selection to the CPU itself: the
  # kernel writes a min/max/EPP window to HWP_REQUEST and the hardware picks a
  # frequency inside it from observed utilisation. The i7-7660U here has no
  # P/E core split -- hybrid topology starts at Alder Lake -- so this scaling is
  # the whole of its power management, alongside the C-states.
  #
  # It judges by *sustained* utilisation, which is right for a compile and wrong
  # for anything that alternates short CPU bursts with waiting on I/O: app
  # startup, page loads, a nix build that spends its time on the disk. Averaged
  # over wall clock those look idle, so the hardware keeps the frequency down
  # and every burst between I/O operations runs slow. EPP=balance_power, which
  # power-profiles-daemon sets on battery, biases it to wait even longer.
  #
  # hwp_dynamic_boost makes intel_pstate watch for iowait wakeups and lift the
  # HWP *floor* for the length of the burst -- not the ceiling, which is already
  # maximum. So it cannot make the CPU faster than it could otherwise go; it
  # stops it choosing to go slow. Measured on this machine before enabling:
  # cpu0 spent 54% of a 5s idle sample in C10 and ~77% across all C-states,
  # which the boost leaves alone, because idle produces no iowait wakeups.
  #
  # Off by default upstream: the boosted bursts cost more power and not every
  # workload repays it. Enabled here because the burst case is exactly the
  # "system should wake up when I ask it to" behaviour wanted, and the
  # steady-state cost is nil.
  #
  # There is no kernel parameter for it and the sysfs value resets each boot,
  # hence a unit. It needs intel_pstate in active mode with HWP and the
  # powersave governor -- all true here. Under the performance governor the
  # floor is already the ceiling and the knob does nothing.
  systemd.services.hwp-dynamic-boost = {
    description = "Enable intel_pstate HWP dynamic boost";
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    # Guarded rather than a bare write: the file exists only when the CPU has
    # HWP and intel_pstate came up in active mode. On a kernel that fell back to
    # acpi-cpufreq this should log and move on, not fail the boot.
    script = ''
      f=/sys/devices/system/cpu/intel_pstate/hwp_dynamic_boost
      if [ -w "$f" ]; then
        echo 1 > "$f"
        echo "hwp_dynamic_boost = $(cat "$f")"
      else
        echo "$f absent or read-only -- intel_pstate not in active HWP mode, nothing to do"
      fi
    '';
  };

  # Quickshell.Bluetooth -> adapters, pairing, connect/disconnect.
  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
    # Headset charge level. bluez only exposes the battery provider interface
    # that Quickshell's BluetoothDevice.battery reads when its experimental
    # features are on; without this the bar shows earphones connected but never
    # how much charge they have left.
    settings.General.Experimental = true;
  };

  # bluez refuses to pair unless *some* agent is registered on the bus to answer
  # its confirmation/PIN callbacks, and Quickshell 0.3.0 registers none --
  # checked directly: no org.bluez.Agent1, AgentManager1 or RegisterAgent string
  # appears anywhere in the quickshell binary. Without an agent the bar can
  # connect devices that are already bonded, but first-time pairing fails with
  # "no agent available". blueman supplies the agent, and that is now the *only*
  # reason it is installed: the escape hatch for profile/codec fiddling moved to
  # bluetui (see home.packages above), which is a terminal app and matches the
  # rest of the desktop. blueman-manager is still on PATH, because the agent and
  # the manager ship in one package and splitting them would mean an overlay
  # rebuilding blueman to delete one binary -- but nothing launches it any more.
  # The applet that actually registers the agent is started per-user by
  # home-manager below.
  services.blueman.enable = true;

  # ...and exactly once. This package ships an XDG autostart entry at
  # $out/etc/xdg/autostart/blueman.desktop, which systemd's xdg-autostart
  # generator turns into app-blueman@autostart.service -- a *second* copy of the
  # applet on top of the home-manager unit. They raced every boot and the loser
  # came up half-initialised:
  #
  #   blueman-applet[2608]: ERROR AgentManager:20 on_register_failed:
  #     /org/bluez/obex/agent/blueman org.bluez.obex.Error.AlreadyExists
  #
  # Which copy wins is a race, so which process owns the pairing agent was
  # nondeterministic. Masking the generated unit leaves home-manager's
  # blueman-applet.service as the single owner. /etc/systemd/user outranks
  # $XDG_RUNTIME_DIR/systemd/generator.late in the user unit search path, so a
  # mask here beats the generator.
  #
  # This also takes out blueman-tray, which the duplicate applet spawned and
  # which had nothing to draw into -- the Quickshell bar implements no
  # SystemTray -- so it just logged GTK assertion failures all session. Verified
  # by stopping the unit live: the tray exited, did not respawn from the
  # surviving applet, and org.blueman.Applet stayed owned.
  systemd.user.units."app-blueman@autostart.service".enable = false;

  # Hold hci_uart back from udev's automatic load so it can be loaded a few
  # seconds later instead. This is an attempt at fixing the Bluetooth setup
  # failure properly rather than recovering from it, and the evidence for it is
  # the timing of the two loads on a boot where recovery was needed:
  #
  #   T+6.6s   hci_uart_bcm loads
  #   T+9.2s   BCM: failed to write update baudrate (-110)   <- ETIMEDOUT
  #   T+11.3s  BCM: Reset failed (-110)                         chip is silent
  #
  #   T+50.5s  hci_uart_bcm reloaded by bluetooth-uart-recover
  #   T+51.2s  BCM: failed to write update baudrate (-16)    <- EBUSY, healthy
  #            adapter registers
  #
  # -110 is the chip not answering; -16 is it answering and the driver moving
  # on. A late load gets -16, an early load gets -110, which is the same
  # conclusion upstream reached for the Apple Broadcom parts -- the 2025 patch
  # adding msleep(200) "waiting for hardware warmup" to btbcm_setup_apple()
  # fixes an identical -110 timeout. That patch is on the USB path and this
  # controller is UART (0xfc18 is the vendor baud-rate command), so it does not
  # apply directly, but the failure it describes is this one.
  #
  # The honest caveat: the reload may succeed because the *first* attempt woke
  # the chip, not because more time had passed. Only this change distinguishes
  # them. If the -110 still appears at T+15s, the warmup theory is wrong and
  # this block should be removed rather than tuned upwards.
  #
  # Blacklisting only suppresses the automatic alias-driven load; an explicit
  # modprobe still works, which is what makes this safe. If the unit below
  # never runs, bluetooth-uart-recover still finds no adapter and still issues
  # its own modprobe, so the fallback survives this change -- which is the only
  # reason blacklisting a module the machine needs is acceptable at all.
  boot.blacklistedKernelModules = [ "hci_uart" ];

  systemd.services.bluetooth-uart-delayed-load = {
    description = "Load hci_uart once the Broadcom controller has warmed up";
    before = [ "bluetooth.service" ];
    wantedBy = [ "bluetooth.service" "multi-user.target" ];
    path = with pkgs; [ kmod coreutils ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    # Ordered before bluetooth.service on purpose. bluez only applies
    # Policy.AutoEnable to an adapter that appears in the normal way, so an
    # adapter arriving after bluetoothd has started can land present but
    # powered down -- the exact failure the recovery unit below has to undo by
    # hand. Loading first keeps the ordinary path ordinary.
    #
    # Eight seconds is a guess, not a measurement: it is comfortably past the
    # 6.6 s that failed and well short of the 50 s that worked, and nothing
    # here needs Bluetooth sooner. The delay is paid on every boot, including
    # the four in five that would have succeeded anyway, which is the price of
    # not having to detect the failure first.
    script = ''
      sleep 8
      modprobe hci_uart || true
    '';
  };

  # The Bluetooth controller on this machine is a Broadcom BCM4350C0 hanging off
  # a UART (dw-apb-uart -> serial0-0 -> hci_uart_bcm), not USB, and its setup
  # handshake is unreliable. Apple's ACPI tables do not expose the chip's reset
  # GPIO in the shape hci_bcm expects, so every boot logs
  #
  #   hci_uart_bcm serial0-0: Unexpected number of ACPI GPIOs: 0
  #   hci_uart_bcm serial0-0: No reset resource, using default baud rate
  #
  # and the driver has no way to physically reset the chip before talking to it.
  # Usually it gets away with this: the baud-rate command comes back -16 (EBUSY)
  # immediately, the driver shrugs, and the adapter registers. Roughly one boot
  # in five the chip does not answer at all --
  #
  #   Bluetooth: hci0: command 0xfc18 tx timeout
  #   Bluetooth: hci0: BCM: failed to write update baudrate (-110)
  #   Bluetooth: hci0: BCM: Reset failed (-110)
  #
  # -- setup aborts, and hci0 stays in setup state forever. /sys/class/bluetooth
  # /hci0 exists, bluetoothd is running and healthy, but no adapter is ever
  # published on D-Bus, so `bluetoothctl list` is empty and the bar shows
  # "bluez not running". Reloading hci_uart re-runs the probe and it works on
  # the retry, which is all this unit does.
  #
  # The check is against D-Bus rather than sysfs on purpose: in the failed state
  # the sysfs node is present and looks perfectly normal, and only bluez's own
  # view distinguishes "controller registered" from "controller wedged".
  #
  # Boot is not failed if recovery does not help -- a laptop without working
  # Bluetooth still boots. The journal line is the signal, and the picker
  # already says "bluez not running" in the UI.
  systemd.services.bluetooth-uart-recover = {
    description = "Re-probe the Broadcom UART Bluetooth controller if bluez got no adapter";
    after = [ "bluetooth.service" ];
    wants = [ "bluetooth.service" ];
    wantedBy = [ "multi-user.target" ];
    path = with pkgs; [ kmod util-linux systemd coreutils gnugrep ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      have_adapter() {
        busctl --system tree org.bluez 2>/dev/null | grep -q '/org/bluez/hci'
      }

      # The driver says so itself when setup aborts, so there is no need to
      # wait out a timeout to infer it. -110 (ETIMEDOUT) specifically: that is
      # the chip not answering at all. The -16 (EBUSY) spelling of the same
      # message is the *healthy* path -- the command bounces immediately, the
      # driver shrugs, and the adapter registers -- so matching the bare
      # string would misfire on every good boot.
      setup_failed() {
        dmesg 2>/dev/null |
          grep -qE "BCM: Reset failed \(-110\)|BCM: failed to write update baudrate \(-110\)"
      }

      # Poll at 200 ms instead of a fixed wait. bluetoothd publishes the
      # adapter a moment after the service reports started, so an immediate
      # single check would misfire on a healthy boot -- but once either the
      # adapter is up or the driver has logged ETIMEDOUT, there is nothing
      # left to wait for.
      #
      # have_adapter is checked first on every pass so a stale failure from an
      # earlier boot-time reload cannot trigger a second re-probe.
      for _ in $(seq 1 75); do
        have_adapter && break
        setup_failed && break
        sleep 0.2
      done

      intervened=no

      if ! have_adapter; then
        intervened=yes
        echo "no bluetooth adapter on the bus; re-probing hci_uart"
        rfkill unblock bluetooth || true
        modprobe -r hci_uart || true
        sleep 1
        modprobe hci_uart || true

        for _ in $(seq 1 15); do
          have_adapter && break
          sleep 1
        done
      fi

      if ! have_adapter; then
        echo "still no bluetooth adapter after re-probe; giving up" >&2
        exit 0
      fi

      # powerOnBoot above is bluez's Policy.AutoEnable, which only fires when
      # the adapter appears in the normal way. One that arrives late, from the
      # reload above or from a soft-block being cleared, can land powered down
      # -- observed exactly that after a manual recovery: adapter present,
      # Powered false, discovery silently finding nothing.
      #
      # Gated on having actually re-probed. Now that bluetooth-uart-delayed-load
      # gets the adapter up before bluetoothd starts, the ordinary path is the
      # normal one again and AutoEnable does this by itself -- forcing it here
      # anyway just raced bluetoothd's own initialisation and logged
      #
      #   Failed to set property Powered on interface org.bluez.Adapter1:
      #
      # with an empty error, on a boot where the adapter was already powered.
      # Harmless, but it is noise in exactly the place someone would look when
      # Bluetooth is genuinely broken.
      if [ "$intervened" = yes ]; then
        adapter=$(busctl --system tree org.bluez 2>/dev/null |
          grep -oE '/org/bluez/hci[0-9]+' | head -1)
        if [ -n "$adapter" ]; then
          busctl --system set-property org.bluez "$adapter" \
            org.bluez.Adapter1 Powered b true || true
        fi
      fi
    '';
  };

  # The WiFi half of the same Broadcom combo part (BCM4350, PCI 14e4:43a3 at
  # 0000:02:00.0) has its own intermittent bring-up failure, and it is a
  # different one from the Bluetooth handshake above -- this is the radio not
  # answering at all rather than a setup command timing out.
  #
  # Observed once in eight boots. The device enumerates perfectly: config space
  # reads work, and the BARs come back byte-for-byte identical to a healthy
  # boot --
  #
  #   pci 0000:02:00.0: [14e4:43a3] type 00 class 0x028000 PCIe Endpoint
  #   pci 0000:02:00.0: BAR 0 [mem 0x92400000-0x92407fff 64bit]
  #   pci 0000:02:00.0: BAR 2 [mem 0x92000000-0x923fffff 64bit]
  #
  # -- and then seven seconds later brcmfmac's first MMIO read comes back all
  # ones and the probe gives up:
  #
  #   brcmfmac: brcmf_chip_recognition: MMIO read failed: 0xffffffff
  #   brcmfmac: brcmf_pcie_probe: failed 14e4:43a3
  #
  # Nothing is logged in between. No AER report, no link-down, no bus error,
  # and pcie_aspm=off is already on the kernel command line so this is not the
  # link being powered down underneath the driver. The chip simply stopped
  # responding between enumeration and probe. Re-enumerating it is the only
  # lever software has left, and it is the same lever `setpci`-era advice and
  # the Broadcom bug reports all land on.
  #
  # The match is on vendor *and* class, not on the 0000:02:00.0 address. The
  # FaceTime HD camera is also a Broadcom part on this machine (14e4:1570 at
  # 0000:03:00.0), so vendor alone would be ambiguous -- class 0x028000 is what
  # separates the network controller from the camera's 0x048000. Matching by
  # property rather than by bus address also means a rescan that lands the card
  # at a different slot does not silently turn this unit into a no-op.
  #
  # The health check is "is there a wireless netdev", not "is brcmfmac bound".
  # A bound driver is not the same as a working radio, and an rfkill block --
  # soft or hard -- leaves the interface present, so the switch being off never
  # triggers a pointless remove/rescan cycle.
  #
  # Ordering is deliberately *after* NetworkManager rather than before it.
  # NetworkManager picks up a wifi device that appears late perfectly well, so
  # there is nothing to gain by holding up the network target, and blocking it
  # would put this unit's retry loop on the critical path of every healthy
  # boot. As written the healthy path breaks out of the first loop iteration
  # and costs nothing.
  #
  # Rescan is scoped to the parent bridge (0000:00:1d.0, derived from the
  # device rather than hardcoded) instead of the global /sys/bus/pci/rescan.
  # A global rescan would also walk Thunderbolt and every other bus, which is
  # a much larger blast radius than this problem justifies.
  #
  # As with Bluetooth, boot is not failed if recovery does not work. A laptop
  # with no wifi still boots, and there is a wired/tethered path to fix it.
  systemd.services.wifi-pcie-recover = {
    description = "Re-enumerate the Broadcom PCIe wifi card if its probe failed";
    after = [ "NetworkManager.service" ];
    wants = [ "NetworkManager.service" ];
    wantedBy = [ "multi-user.target" ];
    path = with pkgs; [ kmod coreutils util-linux ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      have_wifi() {
        for w in /sys/class/net/*/wireless; do
          [ -e "$w" ] && return 0
        done
        return 1
      }

      # brcmfmac announces its own failure, so there is no reason to sit out a
      # fixed timeout waiting to infer it. Both spellings are matched because
      # the chip recognition failure is the specific symptom seen here and the
      # probe failure is the general one -- either is grounds to act.
      probe_failed() {
        dmesg 2>/dev/null |
          grep -qE "brcmf_pcie_probe: failed|brcmf_chip_recognition: MMIO read failed"
      }

      # Broadcom (0x14e4) network controller (class 0x028000). Deliberately not
      # the camera, which is the same vendor with class 0x048000.
      find_wifi_pci() {
        for d in /sys/bus/pci/devices/*; do
          [ "$(cat "$d/vendor" 2>/dev/null)" = "0x14e4" ] || continue
          [ "$(cat "$d/class"  2>/dev/null)" = "0x028000" ] || continue
          echo "$d"
          return 0
        done
        return 1
      }

      # Poll at 200 ms rather than waiting out a fixed delay. Both of the
      # decided outcomes are usually already true by the time this unit runs
      # -- a healthy boot has the interface, and a failed one has logged the
      # failure -- so in practice this exits on the first iteration either
      # way. The loop only ever spins in the narrow window where brcmfmac has
      # not reported one way or the other yet.
      #
      # have_wifi is checked before probe_failed on every pass, so a stale
      # failure left in the ring buffer by an earlier recovery cannot trigger
      # a second, pointless remove/rescan.
      for _ in $(seq 1 75); do
        have_wifi && exit 0
        probe_failed && break
        sleep 0.2
      done

      # Falling out of the loop without a logged failure still means fifteen
      # seconds with no interface. Re-enumerating is the same last resort the
      # fixed-delay version applied, and it is harmless when the device is
      # genuinely absent -- find_wifi_pci below simply finds nothing.
      if have_wifi; then
        exit 0
      fi

      dev=$(find_wifi_pci) || {
        echo "no Broadcom wifi device in sysfs at all; nothing to re-enumerate" >&2
        exit 0
      }

      # Resolve the parent bridge before the remove, because $dev stops
      # existing the moment it succeeds.
      bridge=$(dirname "$(readlink -f "$dev")")

      echo "wifi probe failed; re-enumerating $(basename "$dev") via $(basename "$bridge")"
      echo 1 > "$dev/remove" || true
      sleep 1
      if [ -w "$bridge/rescan" ]; then
        echo 1 > "$bridge/rescan" || true
      else
        echo 1 > /sys/bus/pci/rescan || true
      fi

      for _ in $(seq 1 10); do
        have_wifi && break
        sleep 1
      done

      # The rescan re-probes with brcmfmac already resident, which is usually
      # enough. If the card came back but the driver did not latch onto it,
      # bounce the module so the probe runs from a clean state.
      if ! have_wifi; then
        echo "card re-enumerated but no interface; reloading brcmfmac"
        modprobe -r brcmfmac || true
        sleep 1
        modprobe brcmfmac || true

        for _ in $(seq 1 15); do
          have_wifi && break
          sleep 1
        done
      fi

      if ! have_wifi; then
        echo "still no wifi interface after re-enumeration; giving up" >&2
        exit 0
      fi

      echo "wifi recovered"
    '';
  };

  # Quickshell.Networking talks to NetworkManager, which is already enabled
  # further down (networking.networkmanager.enable), so wifi needs nothing extra.

  # --- Built-in FaceTime HD camera ---
  # This is a MacBookPro14,1 (13-inch, 2017), and its camera is not a USB webcam
  # -- confirmed from sysfs: PCI 0000:03:00.0 is 14e4:1570, the Broadcom 1570
  # PCIe FaceTime HD sensor, class 0x048000. Nothing in the mainline kernel
  # drives it, which is why /dev/video* did not exist and every app reported "no
  # camera".
  #
  # This module supplies the two missing halves:
  #   * patjak's out-of-tree `facetimehd` kernel module, and
  #   * `facetimehd-firmware`, which is NOT redistributable -- the derivation
  #     downloads an Apple macOS driver package and extracts the blob locally.
  #     That is why it is unfree; nixpkgs.config.allowUnfree is already true.
  #
  # Verified before enabling: the module builds against this exact kernel --
  # facetimehd-0.6.13-6.18.48 came prebuilt from cache.nixos.org, so it is not
  # a local compile that might break on the next kernel bump.
  #
  # The module also blacklists `bdc_pci` (an old conflicting driver) and, more
  # importantly, unloads facetimehd across suspend and reloads it on resume --
  # the driver hard-hangs the machine on sleep otherwise. That is handled by the
  # module itself, not something to add here.
  # PORTABILITY: Apple Intel Macs ONLY -- delete these two lines on any other
  # machine. A normal USB webcam needs no configuration whatsoever.
  hardware.facetimehd.enable = true;

  # Sensor colour calibration, also extracted from Apple's driver. Upstream
  # flags it experimental, but without it the picture is noticeably washed out
  # and white-balanced wrong. If the camera misbehaves, this is the first thing
  # to turn off -- it is independent of the module itself.
  hardware.facetimehd.withCalibration = true;

  # --- File manager plumbing ---
  # nautilus itself is installed per-user by home-manager; these are the system
  # services it expects a desktop environment to provide. Outside GNOME nothing
  # else turns them on, and each one is a visible feature if it is missing.
  #
  # gvfs backs the trash:// , recent:// and network:// URIs. Without it "Move to
  # Trash" fails outright and the sidebar's Trash/Recent entries are dead.
  services.gvfs.enable = true;
  # udisks2 is what gvfs asks to mount removable media, so USB sticks and SD
  # cards appear in the sidebar and mount on click instead of doing nothing.
  services.udisks2.enable = true;

  # Right-click -> "Open in kitty". nautilus has no terminal entry at all off
  # GNOME; this module installs the nautilus-python extension, points
  # NAUTILUS_4_EXTENSION_DIR at it, and writes the terminal choice into a
  # system dconf database so it applies without any per-user gsettings step.
  programs.nautilus-open-any-terminal = {
    enable = true;
    # kitty rather than foot: kitty is the terminal carrying the Mac-style tab
    # and copy/paste bindings from home-manager. (foot stays on Super+Return.)
    terminal = "kitty";
  };

  imports =
    [ # Include the results of the hardware scan.
      ./hardware-configuration.nix
      # Hand-written quirks for this MacBookPro14,1 chassis. Kept separate from
      # hardware-configuration.nix because that file is regenerated by
      # nixos-generate-config and would lose anything added to it. Drop this
      # import if the config is ever restored onto other hardware.
      ./hardware-macbookpro14.nix
      # home-manager as a NixOS module: user dotfiles are built and activated
      # as part of `nixos-rebuild switch`, not by a separate `home-manager`
      # command. `home-manager` is the pinned tarball from the let block above.
      (import "${home-manager}/nixos")
    ];

  # Use the systemd-boot EFI boot loader.
  # PORTABILITY: assumes UEFI. On a BIOS/legacy machine use boot.loader.grub
  # instead, or the system will build but refuse to boot.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.loader.systemd-boot.consoleMode = "0";

  # Keep the boot menu to the current generation plus two to fall back to.
  #
  # This bounds the *menu*, not the profile: a rebuild writes at most this many
  # .conf files into /boot/loader/entries and garbage-collects the kernels and
  # initrds that no remaining entry references. The generations themselves stay
  # in /nix/var/nix/profiles, still rollback-able with `nixos-rebuild
  # --rollback` or by switching to system-N-link by hand; only their menu entry
  # is gone. Actually retiring them is `nix-env -p
  # /nix/var/nix/profiles/system --delete-generations`, a separate command that
  # this setting neither performs nor implies.
  #
  # Worth setting because /boot is the 300M EFI partition Apple's installer
  # laid down and it cannot be grown without moving the root partition. The
  # entries are ~400 bytes each and were never the problem; the initrds are 41M
  # apiece. Every rebuild that changes an initrd input -- a kernel module, a
  # firmware package, an fs option -- adds another, and unreferenced ones are
  # only reaped when the last entry pointing at them is dropped. Without a
  # limit no entry is ever dropped, so at 43 generations /boot held four
  # initrds and sat at 61% on a partition where two more would have filled it
  # mid-rebuild, leaving a half-written bootloader.
  boot.loader.systemd-boot.configurationLimit = 3;

  # PORTABILITY: Apple laptop suspend fix. Probably unnecessary elsewhere.
  #
  # /sys/power/mem_sleep on this machine offers "s2idle [deep]" -- the kernel
  # defaults to `deep` (ACPI S3, true suspend-to-RAM). On this MacBookPro14,1
  # that default does not reliably come back: the journal shows the machine
  # reaching "PM: suspend entry (deep)" and then never writing another line,
  # with the next entry being a cold boot. That is a firmware-level hang on
  # resume -- no shutdown, no panic, just gone until the power button is held.
  #
  # s2idle (suspend-to-idle, S0ix) keeps the CPU in its deepest C-state instead
  # of handing control to Apple's S3 path, and resumes reliably. The cost is
  # real: idle drain goes from roughly 1-2%/hour on S3 to more like 5-10%/hour,
  # so an overnight sleep will eat noticeably more battery. That is the trade
  # for a laptop that actually wakes up.
  #
  # To go back to the default, delete this line -- or test one suspend without
  # rebuilding first:
  #     echo deep | sudo tee /sys/power/mem_sleep
  boot.kernelParams = [
    "mem_sleep_default=s2idle"

    # --- Resume survival for the Apple ANS2 NVMe controller ---
    #
    # The SSD is an APPLE SSD AP0128J behind PCI 106b:2003, Apple's own ANS2
    # controller. The kernel already knows it is odd -- it applies
    # NVME_QUIRK_SINGLE_VECTOR, which is why the boot log says
    # "1/0/0 default/read/poll queues" instead of one queue per CPU.
    #
    # What it does NOT apply to this ID is NVME_QUIRK_SIMPLE_SUSPEND, and that
    # is the bug. nvme_suspend() picks between two strategies: shut the
    # controller down and do a full reset on resume, or leave it powered in a
    # host-managed low power state. It only picks the shutdown path when the
    # platform suspends via firmware. Under s2idle it does not, so the ANS2 is
    # left in an NVMe power state it does not actually survive, and it comes
    # back attached but never completing I/O.
    #
    # That is precisely the observed failure. The machine resumes: the kernel
    # runs, niri redraws, the lock screen takes keystrokes. But nothing can
    # read the disk, so PAM cannot exec unix_chkpwd or read /etc/shadow and
    # every password is "wrong", and journald cannot write, which is why the
    # journal has not one line after any suspend -- not even from NetBird,
    # which otherwise logs about forty lines a minute. Rebooting is the only
    # exit because nothing new can be exec'd from /nix/store.
    #
    # Two levers, neither requiring a patched kernel:
    #
    # default_ps_max_latency_us=0 disables APST outright, so the controller is
    # never told to enter the autonomous low power states it mishandles.
    #
    # pcie_aspm=off is the more interesting one. nvme_suspend() also takes the
    # safe shutdown path when ASPM is disabled on the device, so turning ASPM
    # off should route this controller through the same code the missing quirk
    # would have selected. Treat that as reasoned from the driver's logic
    # rather than confirmed -- it is the cheapest thing that could work, and
    # the definitive fix is patching 106b:2003 into nvme_id_table with
    # NVME_QUIRK_SIMPLE_SUSPEND, which costs a full kernel build on a 2017
    # dual-core.
    #
    # Both cost a little idle power. That is a better trade than a machine
    # that cannot come back.
    "nvme_core.default_ps_max_latency_us=0"
    "pcie_aspm=off"

    # --- Resume latency for the Alpine Ridge Thunderbolt controller ---
    #
    # The Thunderbolt 3 controller does not survive s2idle. Going down, the
    # kernel cannot reach it at all -- `tb_cfg_write: -108` (ESHUTDOWN) -- and
    # its ports refuse to enter D3hot. Coming back they will not leave D3cold,
    # so everything behind them is unreachable and the PCI core waits, doubling
    # each time out to pci_dev_wait()'s 60s ceiling:
    #
    #   xhci_hcd 0000:07:00.0: not ready 65535ms after resume; giving up
    #
    # That happens to several devices, all in the noirq phase -- before
    # interrupts are back, before i915 resumes the panel, before userspace is
    # scheduled. So the whole machine is dark for minutes, keyboard backlight
    # included, and no swayidle hook can help: after-resume fires on logind's
    # PrepareForSleep(false), long after this is over.
    #
    # pcie_port_pm=off does not work by the mechanism its name suggests. The
    # ports still reach D3cold. What changes is that pciehp reports "Card not
    # present" and tears the device down immediately rather than waiting -- the
    # kernel stops waiting, not failing. Resume goes from minutes to seconds.
    #
    # It does not make Thunderbolt survive suspend: 07:00.0 stays gone and
    # usb3/usb4 are deregistered, so external USB-C is dead until reboot. That
    # was equally true before -- the old behaviour was minutes of waiting and
    # then the same dead controller. Internal USB (00:14.0) and the SPI
    # keyboard are on other silicon and unaffected.
    #
    # Expect a harmless WARN at pci.c:2202 ("disabling already-disabled
    # device") from the pciehp teardown.
    #
    # Not a fix for the controller, a way of never asking it the question. The
    # heavier alternative is blacklisting the thunderbolt module, at the cost of
    # Thunderbolt data.
    "pcie_port_pm=off"
  ];

  # Keep the NVMe and the root port it hangs off out of D3cold. Linux cannot
  # reliably bring these back on this machine -- the documented symptom on
  # MacBookPro14,x is "Unable to change power state" for exactly the devices
  # under this PCIe switch. Both default to allowing it.
  #
  # A oneshot at boot rather than a pre-suspend hook: the attribute persists
  # once written, and a hook that fails would fail silently at the worst
  # possible moment.
  #
  # PORTABILITY: matched by PCI vendor:device, not by bus address. The obvious
  # version of this hardcodes 0000:01:00.0, which is where the controller
  # happens to sit on this machine -- but this file is meant to restore onto
  # other hardware, and that same address elsewhere is some unrelated device
  # whose power management would then be quietly altered. 106b:2001 / 2003 /
  # 2005 are the three Apple ANS/ANS2 IDs the nvme driver carries explicit
  # entries for; anything else, including every non-Apple machine, matches
  # nothing and the unit is a no-op.
  systemd.services.nvme-no-d3cold = {
    description = "Keep any Apple ANS2 NVMe and its PCIe root port out of D3cold";
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      found=0
      for dev in /sys/bus/pci/devices/*; do
        [ -e "$dev/vendor" ] || continue
        [ "$(cat "$dev/vendor")" = "0x106b" ] || continue
        case "$(cat "$dev/device")" in
          0x2001 | 0x2003 | 0x2005) ;;
          *) continue ;;
        esac

        found=1
        # The controller, and the port it hangs off -- both have to stay out
        # of D3cold or the parent takes the child down with it. The parent of
        # a root port is the host bridge, which has no d3cold_allowed at all,
        # so the -w test is what stops this walking up too far.
        real=$(readlink -f "$dev")
        for target in "$real" "$(dirname "$real")"; do
          f="$target/d3cold_allowed"
          if [ -w "$f" ]; then
            echo 0 > "$f" && echo "d3cold disabled for $(basename "$target")"
          fi
        done
      done

      if [ "$found" = 0 ]; then
        echo "no Apple ANS2 NVMe controller here; nothing to do"
      fi
    '';
  };

  # Closing the lid suspends. This depends on suspend actually working on this
  # machine, which took three separate fixes -- see the long note on the 900s
  # swayidle timer above. If suspend ever becomes fatal again, "lock" is the
  # stopgap: a laptop that stays awake in a bag and runs itself flat is the
  # lesser evil against one that loses the session outright.
  #
  # swayidle's before-sleep event is what puts the lock screen up, so the
  # screen is already locked before the machine goes down rather than after it
  # comes back.
  #
  # settings.Login.* rather than the old services.logind.lidSwitch spelling --
  # the short options still work but warn on eval that they were renamed.
  #
  # HandlePowerKey: logind's default is "poweroff", with no confirmation and no
  # regard for whether the session is merely locked. A stray press at a
  # swaylock prompt therefore kills the session outright. "suspend" makes the
  # key a sleep/wake toggle, which is what the key does on this chassis under
  # macOS anyway. Holding it for ~4s still cuts power at the firmware level, so
  # nothing is lost by giving up the short press.
  services.logind.settings.Login = {
    HandleLidSwitch = "suspend";
    HandleLidSwitchExternalPower = "suspend";
    HandlePowerKey = "suspend";
  };

  # Configure network connections interactively with nmcli or nmtui.
  networking.networkmanager.enable = true;

  # --- NetBird (netbird.io) ---
  # WireGuard-based mesh VPN. `enable = true` is the module's backward-compatible
  # single-client shortcut and is exactly equivalent to:
  #   services.netbird.clients.default = {
  #     port = 51820; name = "netbird"; interface = "wt0"; hardened = false;
  #   };
  # so the daemon is `netbird.service`, the CLI is plain `netbird`, and the
  # tunnel device is `wt0`. Firewall UDP 51820 is opened automatically
  # (clients.<name>.openFirewall defaults to true) so peers on the same LAN or
  # with a public IP can talk directly instead of relaying through TURN.
  #
  # Deliberately NOT using `hardened = true` (which is the default when you
  # declare a client explicitly). Hardened mode runs the daemon as a system user
  # under `ProtectSystem = "strict"`, which makes /etc read-only. NetBird has to
  # publish the netbird DNS zone somehow, and the hardened path assumes
  # systemd-resolved -- the module's polkit grants for org.freedesktop.resolve1.*
  # are all `mkIf config.services.resolved.enable`. On this machine resolved is
  # inactive and DNS is openresolv writing /etc/resolv.conf, which a strict-/etc
  # service cannot do. Running unhardened keeps the daemon as root so resolvconf
  # works. Trade-off: the daemon control socket is not group-restricted, so any
  # local user can drive the VPN -- acceptable on a single-user laptop. To harden
  # later, enable services.resolved and set hardened = true.
  services.netbird.enable = true;

  # Accept network routes advertised by other peers (e.g. a peer exposing a home
  # or office subnet). Without this, routed subnets silently fail to work, which
  # is a confusing way to lose an afternoon. The cost is real though: "client"
  # switches reverse-path filtering from strict to loose, because return traffic
  # for a routed subnet arrives on wt0 rather than the interface the kernel would
  # pick for that source address. If you only ever reach peers directly by their
  # NetBird IP, set this to "none" and keep strict rp_filter.
  services.netbird.useRoutingFeatures = "client";

  # Set your time zone.
  # PORTABILITY: change to your own zone (`timedatectl list-timezones`).
  time.timeZone = "America/Los_Angeles";

  # Configure network proxy if necessary
  # networking.proxy.default = "http://user:password@proxy:port/";
  # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";

  # Select internationalisation properties.
  i18n.defaultLocale = "en_US.UTF-8";
  console = {
    # PORTABILITY: 32px console font, sized for this HiDPI/retina panel. On a
    # 1080p screen it is comically large -- try "ter-v16n".
    font = "ter-v32n";
    packages = with pkgs; [terminus_font ];
    keyMap = "us";
  };

  # Enable CUPS to print documents.
  # services.printing.enable = true;

  # Enable touchpad support (enabled default in most desktopManager).
  # services.libinput.enable = true;

  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;
  # programs.gnupg.agent = {
  #   enable = true;
  #   enableSSHSupport = true;
  # };

  # List services that you want to enable:

  # Enable the OpenSSH daemon.
  # Password login is requested explicitly. Note that NixOS already defaults
  # PasswordAuthentication to true, but it is spelled out here so that the
  # intent is obvious and a future nixpkgs default flip cannot silently lock
  # you out. The `lab` account already has a password set, which is what makes
  # this work -- an account with no password cannot be logged into over SSH
  # regardless of this setting.
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = true;
      KbdInteractiveAuthentication = true;

      # Root may only log in with a key, never a password. Anything exposed to
      # a network gets scanned for `root` with a password within minutes, and
      # `lab` is in `wheel` so `sudo -i` covers every legitimate need for root.
      PermitRootLogin = "prohibit-password";
    };

    # openFirewall defaults to true, so TCP 22 opens by itself. Left explicit
    # because it is the difference between "sshd is running" and "sshd is
    # reachable", and that is not obvious from `enable = true` alone.
    openFirewall = true;
  };

  # Open ports in the firewall.
  # networking.firewall.allowedTCPPorts = [ ... ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  # networking.firewall.enable = false;

  # Copy the NixOS configuration file and link it from the resulting system
  # (/run/current-system/configuration.nix). This is useful in case you
  # accidentally delete configuration.nix.
  # system.copySystemConfiguration = true;

  # This option defines the first version of NixOS you have installed on this particular machine,
  # and is used to maintain compatibility with application data (e.g. databases) created on older NixOS versions.
  #
  # Most users should NEVER change this value after the initial install, for any reason,
  # even if you've upgraded your system to a new NixOS release.
  #
  # This value does NOT affect the Nixpkgs version your packages and OS are pulled from,
  # so changing it will NOT upgrade your system - see https://nixos.org/manual/nixos/stable/#sec-upgrading for how
  # to actually do that.
  #
  # This value being lower than the current NixOS release does NOT mean your system is
  # out of date, out of support, or vulnerable.
  #
  # Do NOT change this value unless you have manually inspected all the changes it would make to your configuration,
  # and migrated your data accordingly.
  #
  # For more information, see `man configuration.nix` or https://nixos.org/manual/nixos/stable/options#opt-system.stateVersion .
  system.stateVersion = "26.05"; # Did you read the comment?

}

