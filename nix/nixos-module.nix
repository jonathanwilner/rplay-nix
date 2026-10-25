# NixOS integration for the rPlay AirPlay 2 receiver.
#
# The vendor binary looks for its assets, fonts and helper daemons under
# /opt/rplay, so this module publishes that path as a stable symlink and keeps
# the rest of the system declarative.
{ self }:
{ config, lib, pkgs, ... }:
let
  cfg = config.services.rplay;
  inherit (lib) mkIf mkForce mkEnableOption mkOption mkDefault types optional optionalString concatStringsSep;

  # Values are shell-quoted: /etc/rplay/conf is sourced by the launcher, so a
  # name containing spaces or parentheses must not become shell syntax.
  assign = name: value: "${name}=${lib.escapeShellArg value}";

  confFile = pkgs.writeText "rplay-conf" (
    concatStringsSep "\n" (
      optional (cfg.name != null) (assign "RPLAY_NAME" cfg.name)
      ++ optional (cfg.audioDevice != null) (assign "RPLAY_AUDIO_DEVICE" cfg.audioDevice)
      ++ optional (!cfg.touchInput) (assign "RPLAY_IAP_TOUCH" "0")
      ++ optional (cfg.decoder != null) (assign "RPLAY_H264_DECODER" cfg.decoder)
      ++ optional (cfg.renderer != null) (assign "RPLAY_SW_RENDER" cfg.renderer)
      ++ optional (cfg.scaleQuality != null) (assign "RPLAY_SCALE_QUALITY" cfg.scaleQuality)
      ++ optional (cfg.bluetoothHidMac != null) (assign "RPLAY_BT_HID_MAC" cfg.bluetoothHidMac)
      ++ optional cfg.suppressTouchReminder "RPLAY_IAP_TOUCH_NO_REMINDER=1"
      ++ cfg.extraEnvironment
    ) + "\n"
  );
in
{
  options.services.rplay = {
    enable = mkEnableOption "the rPlay AirPlay 2 receiver";

    package = mkOption {
      type = types.package;
      default = self.packages.${pkgs.stdenv.hostPlatform.system}.default;
      defaultText = lib.literalMD "`rplay.packages.\${system}.default`";
      description = "The rPlay package to use.";
    };

    name = mkOption {
      type = types.nullOr types.str;
      default = "rPlay";
      description = "The receiver name shown in the iPhone AirPlay list.";
    };

    audioDevice = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "hw:0";
      description = ''
        ALSA device for AirPlay audio. The vendor default is "default", which
        PipeWire often routes to the analogue jack. Use `hw:0` for HDMI.
      '';
    };

    touchInput = mkOption {
      type = types.bool;
      default = true;
      description = ''
        true  — absolute finger taps; needs AssistiveTouch or Zoom on the phone.
        false — external-mouse behaviour, no phone-side setup required.
      '';
    };

    decoder = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "sw";
      description = ''
        H.264 decoder hint. Leave unset for the vendor default. The vendor
        reports that `h264_v4l2m2m` produces no frames and can lock up a
        Raspberry Pi, so hardware decode is not enabled here.
      '';
    };

    scaleQuality = mkOption {
      type = types.nullOr (types.enum [ "0" "1" ]);
      default = "1";
      description = ''
        Scaling filter for the mirror window. "0" is nearest neighbour, which
        the vendor defaults to on ARM and which looks jagged when the 532x1080
        AirPlay stream is enlarged to the window. "1" is linear filtering.
      '';
    };

    renderer = mkOption {
      type = types.nullOr (types.enum [ "0" "1" ]);
      default = null;
      description = ''
        Set to "0" to use SDL's accelerated renderer. ARM builds default to the
        software renderer; the package's emulated x86_64 build keeps that
        default.
      '';
    };

    bluetoothHidMac = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "AA:BB:CC:DD:EE:FF";
      description = "Bluetooth MAC of the iPhone used for BT HID control.";
    };

    suppressTouchReminder = mkOption {
      type = types.bool;
      default = false;
      description = "Stop reminding that iOS needs Accessibility Zoom or AssistiveTouch for touch injection.";
    };

    extraEnvironment = mkOption {
      type = types.listOf types.str;
      default = [ ];
      example = [ "RPLAY_PROXY_IDLE_MS=2500" ];
      description = "Extra `NAME=value` lines appended to /etc/rplay/conf.";
    };

    mdns = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = ''
          Run Apple's mDNSResponder daemon shipped with rPlay. It replaces
          avahi-daemon, which the AirPlay discovery path cannot use.
        '';
      };
      conflictWithAvahi = mkOption {
        type = types.bool;
        default = false;
        description = ''
          Stop avahi-daemon while the rPlay Bonjour daemon runs.

          The vendor unit declares Conflicts=avahi-daemon. In practice both
          responders can hold UDP 5353 at the same time through SO_REUSEPORT:
          measured on armstrong, Apple's mdnsd advertised rPlay while avahi kept
          serving HomeKit accessories and armstrong.local kept resolving. The
          default keeps avahi running so HomeKit discovery survives. Set this to
          true to follow the vendor packaging exactly.
        '';
      };
    };

    openFirewall = mkOption {
      type = types.bool;
      default = true;
      description = "Open the AirPlay TCP ports and mDNS UDP port 5353.";
    };

    desktopIntegration = mkOption {
      type = types.bool;
      default = true;
      description = "Install the desktop entry, icon and autostart helper.";
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [ cfg.package ];

    # The vendor binary has /opt/rplay compiled in for assets, fonts and the
    # helper daemons.
    systemd.tmpfiles.rules = [
      "L+ /opt/rplay - - - - ${cfg.package}/opt/rplay"
    ];

    environment.etc."rplay/conf".source = mkForce confFile;

    networking.firewall = mkIf cfg.openFirewall {
      allowedTCPPorts = [ 7000 ];
      allowedUDPPortRanges = [
        {
          from = 5353;
          to = 5353;
        }
        {
          from = 6000;
          to = 7010;
        }
      ];
    };

    systemd.services.rplay-mdnsd = mkIf cfg.mdns.enable {
      description = "rPlay Bonjour daemon (Apple mDNSResponder)";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];
      conflicts = optional cfg.mdns.conflictWithAvahi "avahi-daemon.service"
        ++ optional cfg.mdns.conflictWithAvahi "avahi-daemon.socket";
      serviceConfig = {
        Type = "forking";
        GuessMainPID = true;
        ExecStart = "${cfg.package}/bin/rplay-mdnsd";
        Restart = "on-failure";
        RestartSec = 2;
      };
    };

    # avahi occupies UDP 5353. Stopping it is what the vendor package does with
    # Conflicts=; this makes the same intent explicit for ordering.
    systemd.sockets.avahi-daemon.wantedBy = mkIf (cfg.mdns.enable && cfg.mdns.conflictWithAvahi) (mkForce [ ]);
    systemd.services.avahi-daemon.wantedBy = mkIf (cfg.mdns.enable && cfg.mdns.conflictWithAvahi) (mkForce [ ]);
  };
}
