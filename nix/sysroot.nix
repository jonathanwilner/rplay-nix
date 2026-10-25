# aarch64 runtime libraries for running the vendor arm64 binaries on an
# x86_64 host through qemu-user. Built on the x86_64 builder with the
# pkgsCross toolchain, so no aarch64 builder is required.
{ pkgs }:
let
  cross = pkgs.pkgsCross.aarch64-multiplatform;
  getLib = p: cross.lib.getLib p;
  roots = map getLib [
    cross.glibc
    cross.stdenv.cc.cc.lib
    cross.freetype
    cross.alsa-lib
    cross.x264
    cross.zlib
    cross.libva
    cross.libx11
    cross.xorg.libXi
    cross.xorg.libXcursor
    cross.xorg.libXrandr
    cross.xorg.libXinerama
    cross.xorg.libXext
    cross.xorg.libXScrnSaver
    cross.libxcb
    cross.libxext
    cross.libxau
    cross.libxdmcp
    cross.libpciaccess
    cross.udev
    cross.bluez
    cross.glib
    cross.dbus
    cross.libuuid
  ];
  closure = pkgs.closureInfo { rootPaths = roots; };
in
pkgs.runCommand "rplay-aarch64-sysroot" { } ''
  mkdir -p $out/lib
  while IFS= read -r p; do
    for d in "$p/lib" "$p/lib64"; do
      [ -d "$d" ] || continue
      for f in "$d"/*.so "$d"/*.so.*; do
        [ -e "$f" ] || continue
        cp -L --no-preserve=mode "$f" "$out/lib/" 2>/dev/null || true
      done
    done
  done < ${closure}/store-paths
  # The guest loader is looked up by absolute path from the ELF interpreter.
  if [ ! -e $out/lib/ld-linux-aarch64.so.1 ]; then
    echo "missing aarch64 loader" >&2
    exit 1
  fi
  echo "rplay sysroot: $(ls $out/lib | wc -l) shared objects" >&2
''
