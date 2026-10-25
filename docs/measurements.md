# Measurements

Host: armstrong — x86_64-linux, NixOS 26.05, kernel 6.14, Intel desktop.
Reference device: Raspberry Pi 4 numbers are the vendor's published figures.

## Build

| Step | Cold | Warm |
|---|---|---|
| `nix build .#packages.x86_64-linux.default` | 7 min 0 s (builds the aarch64 cross sysroot: glib, binutils, icu4c, libical) | 40 s |
| `nix build .#packages.aarch64-linux.default` on goran (N1X, arm64) | 1 min 30 s | — |

Cold x86_64 cost is the one-time aarch64 sysroot. The rPlay payload itself is a
download plus `patchelf`.

## Package contents

| Path | Size |
|---|---|
| `opt/rplay/bin/*` payload | 47 MB (rplay 26 MB, rplay_wd 20 MB, mdnsd 0.7 MB) |
| `libexec/rplay/bin/qemu-aarch64` | 10 MB |
| aarch64 sysroot (`/nix/store/...-rplay-aarch64-sysroot`) | 96 MB |

## Runtime on x86_64 (qemu-user)

Measured with `--autostart`, window open, no iPhone connected:

| Metric | Value |
|---|---|
| Start to "AirPlay servers started" | 26 ms after process start (log deltas) |
| Resident memory | 135 MB (qemu + guest) |
| Threads | 5 |
| CPU, receiver idle with window | ~31% of one core |
| Listening sockets | TCP 7000 (IPv4 + IPv6), UDP 5353 via Apple's mdnsd |

Bonjour check while running:

```
$ avahi-browse -rt _airplay._tcp | grep rPlay
+ enp193s0 IPv4 rPlay (armstrong)    _airplay._tcp    local
+ enp193s0 IPv6 rPlay (armstrong)    _airplay._tcp    local
```

avahi kept running and kept advertising the HomeKit accessories on the same
host, and `armstrong.local` still resolved to 192.168.2.120. Apple's mdnsd and
avahi both hold UDP 5353 through `SO_REUSEPORT`.

## Mirroring on armstrong (measured 25 Oct 2026)

iPhone 16 Pro (`iPhone17,2`, name `JWiPhone`), AirPlay over Wi-Fi, receiver
running as the vendor aarch64 binary under qemu-user.

| Metric | Measured | Vendor, Pi 4 |
|---|---|---|
| Stream resolution | 532 × 1080 | 534 × 1080 |
| Decoded frame rate, animated content | 56–63 fps | 30–49 fps |
| Decoded frame rate, static content | 24–32 fps | — |
| CPU, receiver process | 29.6% of one core | ~1 core of 4 |
| Resident memory | 180 MB | ~250 MB |
| Input injection | Works over iAP, no Bluetooth pairing needed | — |

The low frame rate on static screens is the phone sending fewer frames, not
dropped frames: the counter reports decoded frames per interval.

End-to-end latency was not measured with a stopwatch, so no latency figure is
claimed here.

### What works without Bluetooth

A click at (300, 300) inside the mirror window dismissed Control Centre on the
phone. The log shows `[iap_touch] absolute-touch HID descriptor selected (mouse
skipped)` and `[gui] ios_control_ready=1`, `[gui] bt_hid_ready=0`. Absolute
touch travels over the AirPlay/iAP session, so the Bluetooth pairing the vendor
describes is only needed for the relative-mouse and keyboard path.

### Known warnings on this host

- `[gui] sidebar renderer create failed: Couldn't find matching render driver`.
  Cosmetic: the main window and the mirror both render, and the sidebar window
  is created immediately after.
- `[toast] Failed to pair bluetooth`, `auto_pair_iphone: 'JWiPhone' not found in
  18s scan window`. Expected: the phone is not paired with armstrong at the
  BlueZ level, so the Bluetooth HID path is unavailable.
