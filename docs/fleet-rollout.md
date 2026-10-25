# Fleet rollout

## What was deployed

| Host | Arch | Platform | How |
|---|---|---|---|
| armstrong | x86_64 | NixOS | `services.rplay.enable`, package via `environment.systemPackages`; activated on generation 1815 with `sudo armstrong-deploy-root switch` |
| tweener | x86_64 | NixOS | `services.rplay.enable` in `flake.nix`; applies on that host's next switch |
| sampras | x86_64 | NixOS | same |
| longlen | x86_64 | NixOS | same |
| goran | aarch64 | Ubuntu + Nix | `scripts/install-ubuntu.sh` with the natively built package; `rplay-mdnsd.service` enabled |

The NixOS wiring lives in `~/src/nixos-amd`:

- `flake.nix`: input `rplay = { url = "github:jonathanwilner/rplay"; inputs.nixpkgs.follows = "nixpkgs"; }`,
  added to `desktopSpecialArgs`, module `rplay.nixosModules.default` in `mkDesktopHost`.
- `configuration.nix`: `rplay.packages.${system}.default` in `environment.systemPackages`,
  so the receiver is present on every desktop host whether or not the service runs.
- `services.rplay.enable = true` in the `tweener`, `sampras`, `longlen` and
  `armstrong` host modules.

## Why the service also runs next to avahi

The vendor package declares `Conflicts=avahi-daemon` because both daemons bind
UDP 5353. On this fleet avahi is what advertises Home Assistant's HomeKit
bridge, so replacing it would break accessory discovery in the Home app.

Measured on armstrong with both running:

```
$ avahi-browse -rt _airplay._tcp | grep rPlay
+ enp193s0 IPv4 rPlay (armstrong)    _airplay._tcp    local
$ avahi-resolve -n armstrong.local
armstrong.local 192.168.2.120
$ systemctl is-active avahi-daemon
active
```

Both responders hold UDP 5353 through `SO_REUSEPORT`, each answers for its own
service types, and avahi's hostname claim is unaffected. `services.rplay.mdns.conflictWithAvahi`
defaults to `false` for that reason; set it to `true` on a host where you want
the vendor's behaviour exactly.

If mDNS misbehaves later, the first thing to try is `conflictWithAvahi = true`
and moving rPlay to a host without HomeKit.

## goran (Ubuntu arm64)

Goran is not NixOS, so the flake ships `scripts/install-ubuntu.sh`:

```sh
rsync -a --exclude work --exclude .git ./ goran:/tmp/rplay-flake/
ssh goran 'cd /tmp/rplay-flake && nom-tmux build-rplay-aarch64 -- \
  nix build /tmp/rplay-flake#packages.aarch64-linux.default -o result'
ssh goran 'sudo -n /tmp/rplay-flake/scripts/install-ubuntu.sh $(readlink -f /tmp/rplay-flake/result)'
```

The script installs `/opt/rplay`, writes `/etc/rplay/conf`, adds a GC root for
the store path, installs the desktop entry and icon, and enables
`rplay-mdnsd.service`. Verified on goran: the build is native AArch64 (no qemu
in the launcher), `rplay --help` runs, and the Bonjour daemon is active.

## Verifying a host

```sh
systemctl status rplay-mdnsd
avahi-browse -rt _airplay._tcp | grep -i rplay     # service visible on the LAN
ss -ltnp | grep 7000                               # control port
rplay --help                                       # launcher resolves
```

Then click **Start** in the rPlay window, or launch with `--autostart`, and pick
the receiver in the iPhone's Control Centre.

## Rollback

- NixOS: `sudo armstrong-deploy-root status`, then roll back the system profile
  and re-promote through the guarded path.
- goran: `sudo systemctl disable --now rplay-mdnsd`, `sudo rm /opt/rplay`, and
  remove `/etc/systemd/system/rplay-mdnsd.service`.

## Outcome (24 Oct 2026)

- **armstrong**: deployed. `armstrong-deploy-root switch` promoted
  `/nix/store/pdppsp27v6gh431avn62wzgg11kji29g-nixos-system-armstrong-...`
  (generation 1815) and every critical health gate passed.
  `rplay-mdnsd` is enabled and active, `rplay` is on `PATH`, and the running
  receiver advertises `_airplay._tcp` as `rPlay (armstrong)`.
- **goran**: deployed natively. `/opt/rplay`, `rplay-mdnsd.service` active,
  desktop entry installed, launcher verified.
- **tweener / sampras / longlen**: change is on `origin/main` (`fae1b18d`,
  `30436f1b`); each host applies it on its next system switch.

### What blocked the first attempts

1. `deployment deferred: neTV has active FFmpeg playback and playback
   dependencies changed`. The guard compares the candidate's netv, docker,
   nginx, cloudflare, technitium, network and firewall units against the live
   system and refuses to restart them under an active stream. The candidate
   contained an unrelated, uncommitted Technitium change from another agent, so
   the comparison failed. Deploying from a tree with only the rPlay change made
   the comparison pass and the deployment went through while playback continued.
2. `RPLAY_NAME=rPlay (armstrong)` was written unquoted into `/etc/rplay/conf`,
   which the launcher sources. The parentheses were a shell syntax error, so the
   service crash-looped. Values are now written with `lib.escapeShellArg`; the
   Ubuntu installer uses `printf %q`.

### Known cosmetic effect

Apple's mdnsd cannot claim `armstrong.local` because avahi already owns it, so
it publishes the service with `hostname = armstrong-2.local`. Both names resolve
to 192.168.2.120, HomeKit keeps all 156 `_hap._tcp` records, and AirPlay works.
Setting `services.rplay.mdns.conflictWithAvahi = true` gives mdnsd the primary
name at the cost of HomeKit discovery, so it stays off.
