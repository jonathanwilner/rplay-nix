# rPlay 0.5.0 packaging.
#
# mode = "native":   the aarch64 payload runs directly on this system.
# mode = "emulated": the aarch64 payload runs under qemu-user on x86_64.
#
# The vendor ships aarch64 only. The amd64 package is the same byte-identical
# payload behind a qemu-user launcher.
{
  pkgs,
  lib,
  upstream,
  targetPkgs,
  mode,
  sysroot ? null,
  qemu-user ? null,
}:
let
  isEmulated = mode == "emulated";

  targetLibs = [
    targetPkgs.freetype
    targetPkgs.alsa-lib
    targetPkgs.x264
    targetPkgs.zlib
    targetPkgs.libva
    targetPkgs.libx11
    # SDL2 2.0.22 loads the X11 extensions at runtime; without them the static
    # SDL build reports "No available video device" and the GUI never opens.
    targetPkgs.xorg.libXi
    targetPkgs.xorg.libXcursor
    targetPkgs.xorg.libXrandr
    targetPkgs.xorg.libXinerama
    targetPkgs.xorg.libXext
    targetPkgs.xorg.libXScrnSaver
    targetPkgs.udev
    targetPkgs.bluez
    targetPkgs.glib
    targetPkgs.stdenv.cc.cc.lib
  ];

  libPath = if isEmulated
    then "${sysroot}/lib"
    else lib.makeLibraryPath targetLibs;

  loader = if isEmulated
    then "${sysroot}/lib/ld-linux-aarch64.so.1"
    else "${lib.getLib targetPkgs.glibc}/lib/ld-linux-aarch64.so.1";

  version = upstream.version;
in
pkgs.runCommand "rplay-${version}"
  {
    nativeBuildInputs = [ pkgs.patchelf ];
    # Passed through the environment so the builder script itself stays free of
    # store paths.
    RPLAY_LOADER = loader;
    RPLAY_RPATH = libPath;
    RPLAY_SHELL = "${pkgs.runtimeShell}";
    RPLAY_QEMU = if isEmulated then "${qemu-user}/bin/qemu-aarch64" else "";
    RPLAY_VERSION_DEFAULT = version;
    passthru = { inherit version; };
    meta = {
      description = "rPlay AirPlay 2 receiver (vendor aarch64 build)";
      homepage = "https://github.com/rPlayAI/rplay-linux";
      license = lib.licenses.unfree;
      platforms = [ "aarch64-linux" "x86_64-linux" ];
      mainProgram = "rplay";
    };
  }
  (
  ''
    mkdir -p $out/opt/rplay $out/bin $out/libexec/rplay \
             $out/share/applications $out/share/icons/hicolor/128x128/apps

    cp -a ${upstream.unpacked}/opt/rplay/. $out/opt/rplay/
    chmod -R u+w $out/opt/rplay

    # Vendor ABI for libx264 (SONAME 164). The payload lib directory precedes
    # the sysroot on the rpath, so this copy wins.
    install -m 0755 ${upstream.x264}/libx264.so.164 $out/opt/rplay/lib/libx264.so.164

    rpath="$out/opt/rplay/lib:$RPLAY_RPATH"
    for binary in $out/opt/rplay/bin/rplay \
                  $out/opt/rplay/bin/rplay_wd \
                  $out/opt/rplay/bin/mdnsd; do
      patchelf --set-interpreter "$RPLAY_LOADER" --set-rpath "$rpath" "$binary"
    done
    patchelf --set-rpath "$rpath" $out/opt/rplay/lib/libdns_sd.so

    install -m 0644 ${upstream.unpacked}/usr/share/icons/hicolor/128x128/apps/rplay.png \
      $out/share/icons/hicolor/128x128/apps/rplay.png
    cat > $out/share/applications/rplay.desktop <<'DESKTOP'
    [Desktop Entry]
    Type=Application
    Name=rPlay
    GenericName=AirPlay Receiver
    Comment=Mirror an iPhone or iPad over AirPlay and drive it from this machine
    Exec=rplay
    Icon=rplay
    Terminal=false
    Categories=AudioVideo;Video;Network;
    StartupWMClass=rPlay
    DESKTOP

    # Writes a launcher that applies /etc/rplay/conf, pins the release identity,
    # then executes PAYLOAD (optionally through qemu-user).
    mk_entry() {
      dest="$1"
      payload="$2"
      prefix="$3"
      mkdir -p "$(dirname "$dest")"
      cat > "$dest" <<'ENTRY'
    #!@SHELL@
    set -e
    # System configuration first, then the per-user file so the user wins.
    if [ -r /etc/rplay/conf ]; then
      set -a
      . /etc/rplay/conf
      set +a
    fi
    user_conf="''${XDG_CONFIG_HOME:-''${HOME:-/nonexistent}/.config}/rplay/conf"
    if [ -r "$user_conf" ]; then
      set -a
      . "$user_conf"
      set +a
    fi
    : "''${RPLAY_VERSION:=@VERSION@}"
    export RPLAY_VERSION
    exec @EXEC@ "$@"
    ENTRY
      sed -i \
        -e "s|@SHELL@|$RPLAY_SHELL|" \
        -e "s|@VERSION@|$RPLAY_VERSION_DEFAULT|" \
        -e "s|@EXEC@|$prefix$payload|" \
        "$dest"
      chmod 0755 "$dest"
    }
  ''
  + lib.optionalString isEmulated ''
    mv $out/opt/rplay/bin/rplay $out/libexec/rplay/rplay.aarch64
    mv $out/opt/rplay/bin/rplay_wd $out/libexec/rplay/rplay_wd.aarch64
    mv $out/opt/rplay/bin/mdnsd $out/libexec/rplay/mdnsd.aarch64

    # The receiver resolves sibling helpers through /proc/self/exe, which under
    # qemu points at the emulator. Run a copy of the emulator from a directory
    # that also holds those helpers, so USB host preparation still works.
    mkdir -p $out/libexec/rplay/bin
    install -m 0755 ${qemu-user}/bin/qemu-aarch64 $out/libexec/rplay/bin/qemu-aarch64
    for helper in usb-host-services.sh start-rplay.sh; do
      install -m 0755 $out/opt/rplay/bin/$helper $out/libexec/rplay/bin/$helper
      # qemu reports /proc/self/exe as the guest image, so the receiver also
      # looks for its helpers next to the payload binary.
      install -m 0755 $out/opt/rplay/bin/$helper $out/libexec/rplay/$helper
    done
    ln -s $out/libexec/rplay/rplay_wd.aarch64 $out/libexec/rplay/bin/rplay_wd

    mk_entry $out/bin/rplay $out/libexec/rplay/rplay.aarch64 "$out/libexec/rplay/bin/qemu-aarch64 "
    mk_entry $out/bin/rplay-mdnsd $out/libexec/rplay/mdnsd.aarch64 "$out/libexec/rplay/bin/qemu-aarch64 "
    mk_entry $out/opt/rplay/bin/rplay_wd $out/libexec/rplay/rplay_wd.aarch64 "$out/libexec/rplay/bin/qemu-aarch64 "
  ''
  + lib.optionalString (!isEmulated) ''
    mk_entry $out/bin/rplay $out/opt/rplay/bin/rplay ""
    mk_entry $out/bin/rplay-mdnsd $out/opt/rplay/bin/mdnsd ""
    ln -s $out/opt/rplay/bin/rplay_wd $out/bin/rplay-wd
  ''
  + ''
    ln -s $out/opt/rplay/bin/usb-host-services.sh $out/bin/rplay-usb-host-services
    echo "rplay ${version} (${if isEmulated then "aarch64 under qemu on x86_64" else "native aarch64"})" >&2
  ''
  )
