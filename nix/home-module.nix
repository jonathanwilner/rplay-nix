# Home Manager integration for rPlay.
#
# Home Manager owns everything in the user's home: the package, the per-user
# configuration, the desktop entry and the asset path. Two things stay outside
# its reach and are documented in the host's system bootstrap:
#
#   /opt/rplay              the vendor binary has this path compiled in for
#                           fonts, icons and helper scripts. Point it at
#                           ~/.local/share/rplay/current, which this module
#                           maintains as a store-path symlink.
#   rplay-mdnsd.service     Apple's mDNSResponder binds UDP 5353 and writes
#                           /var/run/mdnsd, so it runs as a system service.
{ self }:
{ config, lib, pkgs, ... }:
let
  cfg = config.programs.rplay;
  inherit (lib) mkIf mkEnableOption mkOption types optional;
  inherit (lib) mkDefault;

  # /etc/rplay/conf is sourced by the launcher, so values are shell-quoted.
  assign = name: value: "${name}=${lib.escapeShellArg value}";

  confText = builtins.concatStringsSep "\n" (
    optional (cfg.name != null) (assign "RPLAY_NAME" cfg.name)
    ++ optional (cfg.audioDevice != null) (assign "RPLAY_AUDIO_DEVICE" cfg.audioDevice)
    ++ optional (cfg.decoder != null) (assign "RPLAY_H264_DECODER" cfg.decoder)
    ++ optional (cfg.scaleQuality != null) (assign "RPLAY_SCALE_QUALITY" cfg.scaleQuality)
    ++ optional (cfg.renderer != null) (assign "RPLAY_SW_RENDER" cfg.renderer)
    ++ optional (cfg.bluetoothHidMac != null) (assign "RPLAY_BT_HID_MAC" cfg.bluetoothHidMac)
    ++ optional cfg.suppressTouchReminder "RPLAY_IAP_TOUCH_NO_REMINDER=1"
    ++ cfg.extraEnvironment
  ) + "\n";
in
{
  options.programs.rplay = {
    enable = mkEnableOption "the rPlay AirPlay 2 receiver";

    package = mkOption {
      type = types.package;
      default = self.packages.${pkgs.stdenv.hostPlatform.system}.default;
      defaultText = lib.literalMD "`rplay.packages.${pkgs.stdenv.hostPlatform.system}.default`";
      description = "The rPlay package to use.";
    };

    name = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "rPlay";
      description = "Receiver name shown in the iPhone AirPlay list. Null keeps the hostname.";
    };

    audioDevice = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "hw:0";
      description = "ALSA device for AirPlay audio.";
    };

    decoder = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "sw";
      description = "H.264 decoder hint. Leave null for the vendor default.";
    };

    scaleQuality = mkOption {
      type = types.nullOr (types.enum [ "0" "1" ]);
      default = "1";
      description = ''
        Mirror scaler. "0" is nearest neighbour (jagged when the 532x1080
        stream is enlarged), "1" is linear filtering.
      '';
    };

    renderer = mkOption {
      type = types.nullOr (types.enum [ "0" "1" ]);
      default = null;
      description = "Set to \"0\" to prefer SDL's accelerated renderer.";
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
      description = "Stop reminding that iOS needs Accessibility Zoom or AssistiveTouch.";
    };

    extraEnvironment = mkOption {
      type = types.listOf types.str;
      default = [ ];
      example = [ "RPLAY_PROXY_IDLE_MS=2500" ];
      description = "Extra `NAME=value` lines appended to the user configuration.";
    };

    desktopEntry = mkOption {
      type = types.bool;
      default = true;
      description = "Install a desktop entry and icon for the receiver.";
    };

    assetPath = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Publish `~/.local/share/rplay/current` as a symlink to the package's
        `opt/rplay` tree. Point `/opt/rplay` at it to satisfy the paths the
        vendor binary has compiled in.
      '';
    };
  };

  config = mkIf cfg.enable {
    home.packages = [ cfg.package ];

    xdg.configFile."rplay/conf".text = mkDefault confText;

    home.file = mkIf cfg.assetPath {
      ".local/share/rplay/current".source = "${cfg.package}/opt/rplay";
    };

    xdg.desktopEntries.rplay = mkIf cfg.desktopEntry {
      name = "rPlay";
      genericName = "AirPlay Receiver";
      comment = "Mirror an iPhone or iPad over AirPlay and drive it from this machine";
      exec = "${cfg.package}/bin/rplay";
      icon = "rplay";
      terminal = false;
      categories = [ "AudioVideo" "Video" "Network" ];
      settings.StartupWMClass = "rPlay";
    };

    xdg.dataFile = mkIf cfg.desktopEntry {
      "icons/hicolor/128x128/apps/rplay.png".source =
        "${cfg.package}/share/icons/hicolor/128x128/apps/rplay.png";
    };
  };
}
