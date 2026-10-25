{
  description = "rPlay 0.5.0 — AirPlay 2 receiver for Linux, packaged for aarch64-linux and x86_64-linux";
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  outputs = { self, nixpkgs }:
    let
      lib = nixpkgs.lib;
      systems = [ "aarch64-linux" "x86_64-linux" ];

      # rPlay is proprietary ("personal use only"), so this flake carries its
      # own package set with allowUnfree. Consumers do not need to allow unfree
      # globally: the module defaults to the package this flake already built.
      pkgsFor = system: import nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };

      forAll = f: lib.genAttrs systems (system: f (pkgsFor system) system);

      mkPackage = pkgs: system:
        let
          upstream = import ./nix/upstream.nix { inherit pkgs; };
          isAarch64 = system == "aarch64-linux";
        in
        pkgs.callPackage ./nix/rplay.nix {
          inherit upstream;
          mode = if isAarch64 then "native" else "emulated";
          targetPkgs = if isAarch64 then pkgs else pkgs.pkgsCross.aarch64-multiplatform;
          sysroot = if isAarch64 then null else import ./nix/sysroot.nix { inherit pkgs; };
          qemu-user = if isAarch64 then null else pkgs.qemu-user;
        };
    in
    {
      packages = forAll (pkgs: system: {
        default = mkPackage pkgs system;

        # Arm64 payload cross-built here, for copying to a native aarch64 host.
        aarch64-payload = pkgs.callPackage ./nix/rplay.nix {
          upstream = import ./nix/upstream.nix { inherit pkgs; };
          mode = "native";
          targetPkgs = pkgs.pkgsCross.aarch64-multiplatform;
          sysroot = null;
          qemu-user = null;
        };
      });

      nixosModules.default = import ./nix/nixos-module.nix { inherit self; };
      nixosModules.rplay = self.nixosModules.default;

      homeManagerModules.default = import ./nix/home-module.nix { inherit self; };
      homeManagerModules.rplay = self.homeManagerModules.default;

      overlays.default = final: prev:
        let
          isAarch64 = final.stdenv.hostPlatform.system == "aarch64-linux";
        in
        {
          rplay = final.callPackage ./nix/rplay.nix {
            upstream = import ./nix/upstream.nix { pkgs = final; };
            mode = if isAarch64 then "native" else "emulated";
            targetPkgs = if isAarch64 then final else final.pkgsCross.aarch64-multiplatform;
            sysroot = if isAarch64 then null else import ./nix/sysroot.nix { pkgs = final; };
            qemu-user = if isAarch64 then null else final.qemu-user;
          };
        };

      checks = forAll (pkgs: system: {
        smoke = pkgs.callPackage ./nix/check.nix {
          package = self.packages.${system}.default;
        };
      });

      formatter = forAll (pkgs: _: pkgs.nixpkgs-fmt);
    };
}
