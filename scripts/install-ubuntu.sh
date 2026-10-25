#!/usr/bin/env bash
# Install rPlay on an Ubuntu/Debian arm64 host from a built Nix package.
#
#   sudo ./install-ubuntu.sh /nix/store/<hash>-rplay-0.5.0
#
# Idempotent: re-running with a new store path repoints /opt/rplay and keeps a
# GC root so garbage collection cannot remove the live package.
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "run as root: sudo $0 <package-store-path>" >&2
  exit 1
fi

PKG="${1:?usage: install-ubuntu.sh /nix/store/<hash>-rplay-0.5.0}"
[ -x "$PKG/bin/rplay" ] || { echo "$PKG does not look like the rPlay package" >&2; exit 1; }

NAME="${RPLAY_NAME:-rPlay ($(hostname -s))}"

install -d -m 0755 /etc/rplay /opt
ln -sfn "$PKG/opt/rplay" /opt/rplay

# The launcher sources this file, so the value must be shell-quoted.
printf 'RPLAY_NAME=%s\n' "$(printf '%q' "$NAME")" > /etc/rplay/conf
chmod 0644 /etc/rplay/conf

install -d -m 0755 /nix/var/nix/gcroots
NIX_STORE_BIN="$(command -v nix-store || echo /nix/var/nix/profiles/default/bin/nix-store)"
"$NIX_STORE_BIN" --add-root /nix/var/nix/gcroots/rplay --indirect -r "$PKG" >/dev/null

install -m 0644 "$PKG/share/applications/rplay.desktop" /usr/share/applications/rplay.desktop
if [ -f "$PKG/share/icons/hicolor/128x128/apps/rplay.png" ]; then
  install -d -m 0755 /usr/share/icons/hicolor/128x128/apps
  install -m 0644 "$PKG/share/icons/hicolor/128x128/apps/rplay.png" \
    /usr/share/icons/hicolor/128x128/apps/rplay.png
fi

cat > /etc/systemd/system/rplay-mdnsd.service <<'UNIT'
[Unit]
Description=rPlay Bonjour daemon (Apple mDNSResponder)
After=network.target

[Service]
Type=forking
GuessMainPID=yes
ExecStart=/opt/rplay/bin/mdnsd
Restart=on-failure
RestartSec=2

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable rplay-mdnsd.service
systemctl restart rplay-mdnsd.service
sleep 2
systemctl --no-pager --lines=0 status rplay-mdnsd.service || true

echo
echo "rPlay installed from $PKG"
echo "Launch it from the application menu, or run: $PKG/bin/rplay"
echo "Bonjour: $(systemctl is-active rplay-mdnsd.service) (avahi may keep running; both hold UDP 5353 through SO_REUSEPORT)"
