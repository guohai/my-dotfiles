# Replacement snd-hda-codec-cs8409 that actually drives this MacBook's speakers.
#
# The mainline driver is not broken exactly -- it binds, it parses the pin
# configuration correctly, and it builds a sound card that looks completely
# healthy from userspace. What it does not do is program the amplifier chips
# Apple wired downstream of the codec. Those sit on an I2C bus hanging off the
# CS8409 and come up muted, so every layer above reports success and nothing
# reaches the speakers. Verified on this machine, from the top down:
#
#   Chrome           stream linked to the sink, volume 1.00, not muted
#   PipeWire         both nodes Running at 48 kHz, zero xruns
#   WirePlumber      active route "Speakers", sink 0.70, not muted
#   ALSA mixer       one PCM control at 100%, no Master/Speaker switch to be
#                    wrong -- the generic parser creates no amp controls
#                    because the codec exposes none
#   speaker-test     wrote pink noise straight to hw:0,0 for 5 s with PipeWire
#                    out of the way (wpctl set-profile <card> 0), no errors,
#                    still silent
#
# So the fault is below ALSA, in the one place software can still fix it. The
# same machine plays fine over Bluetooth, which is what rules out the entire
# software stack and leaves only the amps.
#
# davidjo/snd_hda_macbookpro is the driver that knows how to program them
# (MAX98706, SSM3515 and TAS5764L across the various 2017-2019 models). It is
# not a standalone module: it takes the kernel's own sound/hda tree, replaces
# the Makefiles so only codecs/cirrus is built, drops in its own headers, and
# patches cs8409.c/h. That is what the steps below reproduce.
#
# Upstream ships install.cirrus.driver.sh, which wgets a kernel tarball off
# kernel.org and writes into /lib/modules. Neither works here, so the script is
# not used -- but it is the reference for what this file must do, and it is
# worth re-reading it after a version bump rather than assuming these steps
# still match.

{ lib
, stdenv
, fetchFromGitHub
, kernel
}:

stdenv.mkDerivation rec {
  pname = "snd-hda-codec-cs8409-apple";

  # No tags upstream, so the date of the pinned commit is the only version
  # number available. Bump both together.
  version = "2026-09-06";

  src = fetchFromGitHub {
    owner = "davidjo";
    repo = "snd_hda_macbookpro";
    rev = "89b22ff90b86468b186706861dd18663562defa7";
    hash = "sha256-5iDybAlRG5HldUA24L9+rSlgEiUPZg50K8IYC+Lie4U=";
  };

  # The kernel's *source*, not the build tree. The patches are diffs against
  # mainline sound/hda, so they need the .c files, which the build tree does
  # not carry. Using kernel.src rather than a separately-pinned tarball is what
  # keeps the two halves from drifting: the source and the headers the module
  # compiles against are then guaranteed to be the same release.
  #
  # nixpkgs does apply patches to the kernel it builds, and this unpacks the
  # unpatched tarball, so in principle the two could disagree. In practice
  # nixpkgs carries nothing touching sound/hda, and upstream's own script
  # downloads plain mainline for exactly this purpose.
  kernelSrc = kernel.src;

  nativeBuildInputs = kernel.moduleBuildDependencies;

  unpackPhase = ''
    runHook preUnpack

    cp -r ${src} driver
    chmod -R u+w driver
    mkdir -p build
    tar xf $kernelSrc --strip-components=2 --directory=build \
      'linux-${kernel.version}/sound/hda'

    runHook postUnpack
  '';

  patchPhase = ''
    runHook prePatch

    # Narrow the build to codecs/cirrus. Upstream's Makefiles have every other
    # subdirectory commented out, so this produces exactly one .ko and leaves
    # the rest of the kernel's audio stack alone -- which is the point. We are
    # replacing one codec driver, not the HDA core.
    cp driver/makefiles/Makefile              build/hda/Makefile
    cp driver/makefiles/Makefile_common       build/hda/common/Makefile
    cp driver/makefiles/Makefile_codecs       build/hda/codecs/Makefile
    cp driver/makefiles/Makefile_cirrus       build/hda/codecs/cirrus/Makefile

    # The Apple-specific tables and amp sequences. cirrus_apple.h is the one
    # the patched cs8409.c includes; the patch_cirrus_* headers are included
    # in turn by that.
    cp driver/patch_cirrus/cirrus_apple.h \
       driver/patch_cirrus/patch_cirrus_boot84.h \
       driver/patch_cirrus/patch_cirrus_new84.h \
       driver/patch_cirrus/patch_cirrus_real84.h \
       driver/patch_cirrus/patch_cirrus_real84_i2c.h \
       driver/patch_cirrus/patch_cirrus_hda_generic_copy.h \
       build/hda/codecs/cirrus/

    cd build/hda
    patch -p1 < ../../driver/patch_cs8409.c.diff
    patch -p1 < ../../driver/patch_cs8409.h.diff
    cd ../..

    runHook postPatch
  '';

  # Written out rather than driven through makeFlags, because `make -C <kernel>`
  # moves make's CURDIR into the kernel build tree -- so an `M=$(CURDIR)/...`
  # would resolve against the wrong directory. Capturing the path in a shell
  # variable first sidesteps that entirely.
  #
  # -DAPPLE_CODECS and -DAPPLE_PINSENSE_FIXUP are what switch on the amp
  # programming and the jack-sense handling; without them the patched source
  # compiles down to something very close to mainline and stays silent.
  # CONFIG_SND_HDA_RECONFIG=1 is needed because the driver reconfigures the
  # codec after it has already been parsed.
  buildPhase = ''
    runHook preBuild

    make -C ${kernel.dev}/lib/modules/${kernel.modDirVersion}/build \
      M=$PWD/build/hda \
      CFLAGS_MODULE="-DAPPLE_PINSENSE_FIXUP -DAPPLE_CODECS -DCONFIG_SND_HDA_RECONFIG=1 -Wno-unused-variable -Wno-unused-function" \
      modules

    runHook postBuild
  '';

  # INSTALL_MOD_DIR=updates, not the module's natural kernel/sound/hda/codecs/
  # cirrus path. depmod searches updates/ before kernel/, so the in-tree
  # snd-hda-codec-cs8409.ko stays where it is and this one wins the lookup.
  # Installing over the original would work too, right up until something
  # rebuilt the module tree.
  #
  # DEPMOD=true because modules_install would otherwise run depmod against
  # $out, which contains no kernel. NixOS runs the real depmod when it
  # assembles the final module tree.
  #
  # The install step prints a "SIGN ... sign-file: No such file or directory"
  # error regardless of CONFIG_MODULE_SIG_ALL=n. It is not fatal and not worth
  # chasing: this kernel has CONFIG_MODULE_SIG unset entirely, so nothing
  # checks signatures, and the module is compressed and installed either way.
  # Noted here only so the next person reading a build log does not go looking
  # for a problem that is not there.
  installPhase = ''
    runHook preInstall

    make -C ${kernel.dev}/lib/modules/${kernel.modDirVersion}/build \
      M=$PWD/build/hda \
      INSTALL_MOD_PATH=$out \
      INSTALL_MOD_DIR=updates \
      CONFIG_MODULE_SIG_ALL=n \
      DEPMOD=true \
      modules_install

    runHook postInstall
  '';

  meta = with lib; {
    description = "CS8409 HDA codec driver with Apple amplifier support (MacBookPro14,1)";
    homepage = "https://github.com/davidjo/snd_hda_macbookpro";
    license = licenses.gpl2Only;
    platforms = [ "x86_64-linux" ];
    # The 6.17 sound/hda reorganisation is baked into the paths above, and the
    # patches are cut against it. Anything older needs upstream's separate
    # install.cirrus.driver.pre617.sh, which this does not implement.
    broken = lib.versionOlder kernel.version "6.17";
  };
}
