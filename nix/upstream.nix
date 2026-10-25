# The proprietary rPlay 0.5.0 release. Fetched from the vendor, never
# redistributed here: the licence permits personal use only.
{ pkgs }:
let
  tarball = pkgs.fetchurl {
    url = "https://github.com/rPlayAI/rplay-linux/releases/download/v0.5.0/rplay-0.5.0-linux-aarch64.tar.gz";
    hash = "sha256-SmOxcXizdsxxxFsLG5O//XLs8FYsJT57nia5TwBp3xU=";
  };
  # rPlay links libx264 with SONAME 164 (x264 build 0.164.3095, the version in
  # Raspberry Pi OS Bookworm). nixpkgs ships a newer snapshot whose SONAME is
  # 165, so the vendor's expected ABI is fetched from Debian and shipped in the
  # package instead of relying on a symlink.
  x264Deb = pkgs.fetchurl {
    url = "http://ftp.debian.org/debian/pool/main/x/x264/libx264-164_0.164.3095+gitbaee400-3_arm64.deb";
    hash = "sha256-lUdYVmEflxr/4t+szIUlPRxrsvyx1nwxR7MgIc8wS44=";
  };
  deb = pkgs.fetchurl {
    url = "https://github.com/rPlayAI/rplay-linux/releases/download/v0.5.0/rplay_0.5.0_arm64.deb";
    hash = "sha256-r5angN/mxEWDMuRykYPLJPksdFuxslrS7UQ+Faa2/9E=";
  };
in
{
  inherit tarball deb;
  version = "0.5.0";

  # libx264.so.164 extracted from the Debian arm64 package.
  x264 = pkgs.runCommand "libx264-164" { nativeBuildInputs = [ pkgs.binutils pkgs.xz pkgs.patchelf ]; } ''
    mkdir -p $out work
    cd work
    ar x ${x264Deb}
    tar xf data.tar.xz
    cp usr/lib/aarch64-linux-gnu/libx264.so.164 $out/
    patchelf --set-rpath "" $out/libx264.so.164 2>/dev/null || true
  '';

  # Tarball laid out as a normal root: ./opt/rplay, ./usr/share, ./lib/systemd.
  unpacked = pkgs.runCommand "rplay-0.5.0-upstream" { } ''
    mkdir -p $out
    tar xzf ${tarball} -C $out --strip-components=1
  '';
}
