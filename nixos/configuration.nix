# Edit this configuration file to define what should be installed on
# your system. Help is available in the configuration.nix(5) man page, on
# https://search.nixos.org/options and in the NixOS manual (`nixos-help`).
#
# ############################################################################
# ##  STOP -- CHANGE THESE THREE THINGS BEFORE YOU REBUILD                  ##
# ############################################################################
#
# This is someone else's laptop config. It was written for a MacBookPro14,1
# (13-inch Intel, 2017) running niri on Wayland, for a user named `brent`.
# Rebuilding it unchanged will create the wrong user and try to build a camera
# driver for hardware you almost certainly do not have.
#
# Find every machine-specific line with:
#     grep -n 'PORTABILITY:' configuration.nix
#
# ---------------------------------------------------------------------------
# 1. YOUR USERNAME  -- everybody has their own; this one says `brent`
# ---------------------------------------------------------------------------
#    The name `brent` appears in TWO places that must be changed TOGETHER:
#        users.users.brent          (the system account)
#        home-manager.users.brent   (that account's dotfiles)
#    plus one cosmetic spot: the `--user brent` flag on the tuigreet login
#    command, which just prefills the username on the login screen.
#
#    Change all of them at once:
#        sed -i 's/\bbrent\b/YOURNAME/g' configuration.nix
#
#    If you rename only the first, the build still SUCCEEDS -- home-manager
#    quietly configures a user that does not exist, and you log in to a
#    completely unconfigured desktop with no bar, no keybinds and no shell
#    setup. That failure is silent, which is why it is listed first here.
#
# ---------------------------------------------------------------------------
# 2. YOUR CAMERA  -- everybody's is different; this one is an Apple internal
# ---------------------------------------------------------------------------
#    hardware.facetimehd.enable / .withCalibration are for Apple Intel Macs
#    ONLY. The camera in these machines is not a USB webcam -- it is a Broadcom
#    1570 sensor sitting on the PCIe bus (PCI id 14e4:1570), which needs an
#    out-of-tree kernel module plus a firmware blob extracted from a macOS
#    driver package.
#
#    * On any non-Apple machine: DELETE both lines. Nearly every other webcam,
#      internal or USB, is UVC and works with zero configuration -- the kernel
#      driver is already built in. Plug it in, /dev/video0 appears, done.
#    * On an Apple Silicon Mac: DELETE both lines too. This driver is for Intel
#      Macs; Apple Silicon cameras are handled elsewhere entirely.
#    * Keeping them on the wrong hardware costs you a pointless out-of-tree
#      module build on every kernel update, and can break rebuilds outright
#      when that module fails to compile against a newer kernel.
#
#    To check what you actually have, after booting:
#        lsusb | grep -i cam          # a USB/UVC webcam shows up here
#        ls /sys/class/video4linux/   # any working camera shows up here
#
# ---------------------------------------------------------------------------
# 3. YOUR DISKS  -- hardware-configuration.nix is NOT in this repo
# ---------------------------------------------------------------------------
#    It is excluded on purpose: it contains the original laptop's filesystem
#    UUIDs, which are meaningless on your machine and will not boot. Generate
#    your own and never copy anyone else's:
#        sudo nixos-generate-config
#    Until you do, the first build fails with
#        error: path '.../hardware-configuration.nix' does not exist
#    That is expected, not a broken repo.
#
# ############################################################################
#
# ALSO WORTH REVIEWING (these will work as-is, they just may not suit you):
#
#   * boot.loader.systemd-boot -- assumes UEFI. A BIOS/legacy machine needs
#     boot.loader.grub instead, or the system builds fine and then will not
#     boot.
#   * boot.kernelParams = [ "mem_sleep_default=s2idle" ] -- an Apple laptop
#     suspend fix. Harmless elsewhere, but it costs battery: s2idle drains
#     noticeably faster than the kernel default. Delete it on non-Apple
#     hardware.
#   * time.timeZone -- set to America/Los_Angeles.
#   * console.font = "ter-v32n" -- a 32px console font, sized for a HiDPI
#     retina panel. On a 1080p screen it is comically large; try "ter-v16n".
#   * The Mac-style key remapping maps the Super/Windows key to Cmd. That works
#     fine on a PC keyboard, but the muscle memory it targets is macOS'. If you
#     have never used a Mac, you may simply not want the xremap section at all.
#
# SAFE EVERYWHERE, no changes needed: the niri/Quickshell desktop, terminals
# (kitty + foot), fish, Zed, mpv, the lock screen, the audio/bluetooth/wifi
# pickers, clipboard history, screenshots, screen recording, NetBird, sshd.
# ############################################################################

{ config, lib, pkgs, ... }:

let
  # home-manager pinned by hash rather than pulled from a channel, so the
  # version lives in this file and rebuilds are reproducible. To upgrade, bump
  # the branch in the URL and refresh the hash with:
  #   nix-prefetch-url --unpack <url>
  home-manager = builtins.fetchTarball {
    url = "https://github.com/nix-community/home-manager/archive/release-26.05.tar.gz";
    sha256 = "0fyjh6bv6p72ynz0pjkzlf1966h2dq40ivwbzy73lk45aqam1ymh";
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
    images=(${lib.concatStringsSep " " (map (w: "${w}") lockWallpapersBlurred)})
    # $RANDOM is bash's, and this script runs under bash via writeShellScriptBin.
    pick="''${images[$((RANDOM % ''${#images[@]}))]}"

    # No --effect-blur: these images are already blurred, in the store, at
    # panel resolution. See the `preblur` comment above for why.
    #
    # --fade-in is down from 0.4 to 0.15. With the blur precomputed it was the
    # last thing between the keypress and a readable clock. Put it back, or
    # drop the flag, to taste.
    #
    # Do NOT put comments between the flags below. Every line here ends in a
    # backslash, so a `#` does not start a comment on its own line -- it eats
    # the rest of the joined line and terminates the command early. Doing that
    # silently drops every flag after it, and since this is `exec`, nothing
    # complains: you just get a lock screen with the wrong colours.
    exec ${swaylockPkg}/bin/swaylock \
      --image "$pick" \
      --scaling fill \
      --effect-vignette 0.4:0.4 \
      --ignore-empty-password \
      --clock \
      --weekstr '%a' \
      --timestr '%H:%M' \
      --datestr '%-d %b' \
      --batstr '{icon} {p}%' \
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
      "$@"
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

  # Interactive shell for the brent account. Enabling it here (rather than just
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
    # Install user packages into /etc/profiles/per-user/brent.
    useUserPackages = true;
    # Instead of aborting when an unmanaged dotfile is in the way, rename it to
    # <name>.hm-bak. This is what makes the first switch survive the existing
    # hand-written kitty.conf / foot.ini.
    backupFileExtension = "hm-bak";

    users.brent = { ... }: {
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
          {
            timeout = 330;
            command = "${pkgs.niri}/bin/niri msg action power-off-monitors";
            resumeCommand = "${pkgs.niri}/bin/niri msg action power-on-monitors";
          }
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
        };
      };

      home.packages = [
        # The bar's audio popup shells out to pavucontrol for the per-app mixer.
        # Building a full mixer in QML is possible via Quickshell.Services.
        # Pipewire, but pavucontrol already does it well.
        pkgs.pavucontrol

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
  # PORTABILITY: *** CHANGE ME *** the username `brent` is hardcoded here AND
  # in `home-manager.users.brent` further down. Rename BOTH together with
  #     sed -i 's/\bbrent\b/YOURNAME/g' configuration.nix
  # If you rename only this one the build still SUCCEEDS, but home-manager
  # configures a user that does not exist and you log in to a bare desktop
  # with no bar, no keybinds and no shell setup. The failure is silent.
  users.users.brent = {
    isNormalUser = true;
    description = "brent";
    # input  -> read /dev/input/event* (xremap grabs the keyboard)
    # uinput -> write /dev/uinput (xremap emits the rewritten events)
    extraGroups = [ "wheel" "networkmanager" "video" "audio" "docker" "input" "uinput" ];
    # fish is not POSIX-compatible (`export X=y` is `set -x X y`, and bash
    # snippets cannot be `source`d). root is deliberately left on bash so
    # there is always a POSIX recovery shell if a fish change goes wrong.
    shell = pkgs.fish;
  };

  nixpkgs.config.allowUnfree = true;

  environment.systemPackages = with pkgs; [
    nodejs
    # Installed system-wide so every account gets it. The old npm -g install
    # lived under /root/.npm-global, which is unreachable from the brent user
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
    # Super+Shift+3/4 binds. kooha records the screen through
    # xdg-desktop-portal, which programs.niri.enable already sets up
    # (gnome+gtk backends, niri-portals.conf).
    grim
    slurp
    satty
    kooha
    # Stays system-level: xremap needs the input/uinput groups and a system
    # udev rule, so managing it per-user would split the config in two.
    xremapNiri
    # kitty, foot and quickshell are NOT here -- home-manager installs them
    # for the brent user alongside their config (see home-manager.users.brent).
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
  };

  services.greetd = {
    enable = true;
    settings = {
      default_session = {
        # --user brent prefills the login form with the brent account. Do not add
        # --remember: it overwrites the prefill with whoever logged in last
        # (which is how root kept coming back). Press Esc at the password
        # prompt to type a different username.
        command = "${pkgs.tuigreet}/bin/tuigreet --time --user brent --cmd niri-session";
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
  # "no agent available". blueman supplies the agent; blueman-manager is also
  # the escape hatch for profile/codec fiddling, the way pavucontrol is for
  # audio. The applet that actually registers the agent is started per-user by
  # home-manager below.
  services.blueman.enable = true;

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
  # PORTABILITY: *** CHANGE ME *** Apple Intel Macs ONLY.
  # DELETE both of these lines on any other machine -- including Apple Silicon.
  # Nearly every other webcam (internal or USB) is UVC and needs zero config:
  # the kernel driver is built in, /dev/video0 just appears. Keeping this on
  # the wrong hardware buys you a pointless out-of-tree module build on every
  # kernel update, and can break rebuilds when it fails to compile.
  # Check what you have with: ls /sys/class/video4linux/
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
  boot.kernelParams = [ "mem_sleep_default=s2idle" ];

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
  # you out. The `brent` account already has a password set, which is what makes
  # this work -- an account with no password cannot be logged into over SSH
  # regardless of this setting.
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = true;
      KbdInteractiveAuthentication = true;

      # Root may only log in with a key, never a password. Anything exposed to
      # a network gets scanned for `root` with a password within minutes, and
      # `brent` is in `wheel` so `sudo -i` covers every legitimate need for root.
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

