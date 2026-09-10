# luvus -- "mission control for your AI coding agents": a Rust TUI that
# multiplexes several coding-agent sessions (Claude Code, Codex, opencode, ...)
# in one workspace.
#
# Not in nixpkgs yet, so this is vendored here. It is upstream's own
# nix/package.nix from the v0.13.4 tag, verbatim except that the two
# `lib.fakeHash` placeholders are filled in -- upstream ships it with
# placeholders precisely so a packager fills them in. Upstream intends this file
# to land at pkgs/by-name/lu/luvus/package.nix; when it does, delete this file
# and switch to plain `pkgs.luvus`.
#
# To bump: change `version`, set both hashes back to lib.fakeHash, build twice,
# and paste in the hashes Nix reports.
{
  lib,
  rustPlatform,
  fetchFromGitHub,
  makeWrapper,
  git,
  gh,
  openssh,
  bashInteractive,
  coreutils,
  procps,
  sqlite,
  stdenv,
}:

rustPlatform.buildRustPackage (finalAttrs: {
  pname = "luvus";
  version = "0.13.4";

  # Required for new by-name packages (nixpkgs-vet NPV-166).
  __structuredAttrs = true;

  src = fetchFromGitHub {
    owner = "RizRiyz";
    repo = "luvus";
    tag = "v${finalAttrs.version}";
    hash = "sha256-OA0hP6Y8t5J14+fdjxZYcFaJw7kNcp+RHQBKhWCUyhQ=";
  };

  cargoHash = "sha256-ey6ABOcnXT79L7adbWZyAYor6aHv3xPxpfZfrtJzTRM=";

  nativeBuildInputs = [ makeWrapper ];

  # On macOS, Cargo.toml deliberately links the SYSTEM sqlite
  # (/usr/lib/libsqlite3.dylib) instead of bundling it, so the crate passes
  # `-lsqlite3` at the final link. The Nix build sandbox has no /usr/lib, so
  # the link fails with `ld: library not found for -lsqlite3`. Provide nixpkgs'
  # sqlite on Darwin: the link resolves, and the dylib lands in the runtime
  # closure. Linux keeps rusqlite's bundled engine and needs nothing extra.
  buildInputs = lib.optionals stdenv.hostPlatform.isDarwin [ sqlite ];

  # The test suite spawns real PTYs, `ps`, and child processes and reads $HOME,
  # all awkward inside the Nix sandbox; upstream CI runs the full suite on every
  # push, so the package build just compiles the release binary.
  doCheck = false;

  # luvus shells out to these at runtime; bake them into PATH because NixOS has
  # no implicit global one. The user's own PATH is still appended, so a newer
  # git/gh they installed wins. `ps` is Linux-only here (procps); on Darwin the
  # system `ps` is used.
  postFixup = ''
    wrapProgram $out/bin/luvus \
      --prefix PATH : ${
        lib.makeBinPath (
          [
            git
            gh
            openssh
            bashInteractive
            coreutils
          ]
          ++ lib.optionals stdenv.hostPlatform.isLinux [ procps ]
        )
      }
  '';

  meta = {
    description = "Mission control for your AI coding agents";
    homepage = "https://luvus.dev";
    changelog = "https://github.com/RizRiyz/luvus/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.asl20;
    mainProgram = "luvus";
    maintainers = with lib.maintainers; [ rizriyz ];
    platforms = lib.platforms.unix;
  };
})
