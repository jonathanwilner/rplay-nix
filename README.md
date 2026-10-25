# rPlay 0.5.0 for Linux — Nix flake

This repository packages the rPlay AirPlay 2 receiver for two architectures:

| Target | How it runs | Status |
|---|---|---|
| `aarch64-linux` | Vendor aarch64 binaries, native | Same machine code as the published Raspberry Pi release |
| `x86_64-linux` | Vendor aarch64 binaries under `qemu-user` | Working; decode and render run through QEMU's JIT |

The vendor publishes no source and no x86_64 build. `https://github.com/rPlayAI/rplay-linux`
ships `v0.5.0` for arm64 only, under a personal-use licence that forbids
redistribution. This flake downloads the release from the vendor at build time
and never mirrors it.

## Why an emulation layer on x86_64

`rplay` is 27 MB of statically linked FFmpeg 5.1, OpenSSL 1.1.1w, SDL2 2.0.22,
Dear ImGui, FDK-AAC and Apple's AirPlayAudio SDK, plus a 20 MB USB daemon and
Apple's mDNSResponder. Rebuilding it natively for x86_64 means reconstructing
the proprietary application layer; `re/` carries the reverse-engineering
evidence and decompiled source that work starts from.

Until that reconstruction is finished, the x86_64 package runs the unmodified
aarch64 payload through `qemu-user`. Every byte of receiver logic is the
vendor's own.

## Use

```sh
# Standalone
nix run github:jonathanwilner/rplay
nix build .#packages.x86_64-linux.default

# NixOS
{
  inputs.rplay.url = "github:jonathanwilner/rplay";
  # ...
  imports = [ inputs.rplay.nixosModules.default ];
  services.rplay = {
    enable = true;
    name = "rPlay";
  };
}
```

`services.rplay` installs the package, publishes `/opt/rplay` (the vendor
binary has that path compiled in), writes `/etc/rplay/conf`, runs Apple's
Bonjour daemon on UDP 5353 instead of avahi, and opens the AirPlay ports.

Options: `name`, `audioDevice`, `decoder`, `renderer`, `bluetoothHidMac`,
`suppressTouchReminder`, `extraEnvironment`, `mdns.enable`,
`mdns.conflictWithAvahi`, `openFirewall`, `desktopIntegration`.

## Layout

```
flake.nix                 packages, module, overlay, checks
nix/upstream.nix          vendor release, pinned by SHA-256
nix/rplay.nix             packaging for both modes
nix/sysroot.nix           aarch64 runtime libraries for the x86_64 package
nix/nixos-module.nix      system integration
nix/check.nix             build-time smoke test
docs/                     measurements, porting notes, fleet rollout
```

## Measured behaviour

See `docs/measurements.md`. The amd64 build is validated for start-up,
Bonjour registration and the mirroring pipeline; frame rate under QEMU is
lower than the Pi 4 baseline and is reported there with the hardware used.

## Licence

rPlay itself is proprietary, personal use only. This packaging is provided
for Jonathan Wilner's own hardware. The flake's own files are MIT.
