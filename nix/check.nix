# Build-time smoke test: the receiver starts, prints its option list, and the
# packaged tree keeps the layout the vendor binary expects.
{ pkgs, package }:
pkgs.runCommand "rplay-smoke"
  {
    nativeBuildInputs = [ pkgs.gnugrep pkgs.coreutils ];
  }
  ''
    export HOME=$TMPDIR/home
    mkdir -p "$HOME"

    test -x ${package}/opt/rplay/bin/rplay_wd
    test -e ${package}/opt/rplay/lib/libdns_sd.so
    test -e ${package}/opt/rplay/share/fonts/Inter-Regular.ttf

    help="$(${package}/bin/rplay --help 2>&1 || true)"
    echo "$help"
    echo "$help" | grep -q 'Password protected airplay support'
    echo "$help" | grep -q 'Number of zones'

    touch "$out"
  ''
