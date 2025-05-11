{
  description = "Raspberry Pi 4 Base System for RV CANbus Filtering with SOPS & Impermanence (NixOS 24.11)";

  inputs = {
    # Stable channel for the bulk of your system
    nixpkgs = { url = "nixpkgs/nixos-24.11"; };

    # Only pull in unstable to build Caddy with plugins
    nixpkgsUnstable = { url = "nixpkgs/nixos-unstable"; };

    # Rename hyphenated flakes to valid identifiers
    nixosGenerators = {
      url                  = "github:nix-community/nixos-generators";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    sopsNix = {
      url                  = "github:mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    rvc2api = { url = "github:carpenike/rvc2api"; };
  };

  outputs = { self
            , nixpkgs
            , nixpkgsUnstable
            , nixosGenerators
            , sopsNix
            , rvc2api
            , ... }: let

    system = "aarch64-linux";

    # Pi‑4 hardware support
    nixosHardware = builtins.fetchTarball {
      url    = "https://github.com/NixOS/nixos-hardware/archive/8f44cbb48c2f4a54e35d991a903a8528178ce1a8.tar.gz";
      sha256 = "0glwldwckhdarp6lgv6pia64w4r0c4r923ijq20dcxygyzchy7ai";
    };

    # All of your common modules
    commonModules = [
      ./hardware-configuration.nix
      "${nixosHardware}/raspberry-pi/4"
      sopsNix.nixosModules.sops

      ./modules/bootstrap-check.nix
      ./modules/caddy.nix
      ./modules/cloudflared.nix
      ./modules/canbus.nix
      ./modules/glances-web.nix
      ./modules/hwclock.nix
      ./modules/watchdog.nix
      ./modules/secrets.nix
      ./modules/system.nix
      ./modules/boot.nix
      ./modules/motd.nix
      ./modules/networking.nix
      ./modules/users.nix
      ./modules/services.nix
      ./modules/storage.nix
      ./modules/shell.nix
      ./modules/ssh.nix
      ./modules/sudo.nix
      ./modules/systemPackages.nix
      ./modules/rvc.nix
    ];

  in {
    ############################################################################
    # 1) Standalone packages (rvc2api & SD‑card image)
    ############################################################################
    packages.${system} = {
      rvc2api = rvc2api.defaultPackage.${system};

      sdcard = nixosGenerators.nixosGenerate {
        system  = system;
        format  = "sd-aarch64";
        modules = commonModules;
      };
    };

    ############################################################################
    # 2) Your NixOS system configuration
    ############################################################################
    nixosConfigurations.nixpi = nixpkgs.lib.nixosSystem {
      inherit system;

      modules = commonModules ++ [

        # ────────────────────────────────────────────────────────────────────
        # site‑specific overrides for rvc, rvc2api, cloudflared, caddy
        ( { config, pkgs, lib, ... }: {
            services.rvc.console.enable    = true;
            services.rvc.debugTools.enable = true;

            services.rvc2api = {
              enable      = true;
              package     = rvc2api.defaultPackage.${system};
              specFile    = "/etc/nixos/files/rvc.json";
              mappingFile = "/etc/nixos/files/device_mapping.yml";
              channels    = [ "can0" "can1" ];
              bustype     = "socketcan";
              bitrate     = 500000;
            };

            services.rvcCloudflared = {
              enable   = true;
              hostname = "rvc.holtel.io";
              service  = "http://localhost:8000";
            };

            services.rvcCaddy = {
              enable      = true;
              hostname    = "rvc.holtel.io";
              backendPort = 80;
              email       = "ryan@ryanholt.net";
            };
          }
        )
      ];

      # ────────────────────────────────────────────────────────────────────
      # overlays: allowMissingModules + Caddy→unstable.withPlugins
      # ────────────────────────────────────────────────────────────────────
      nixpkgs.overlays = [

        # a) let your modules reference missing attrs without breaking
        (final: super: {
          makeModulesClosure = args:
            super.makeModulesClosure (args // { allowMissing = true; });
        })

        # b) override pkgs.caddy with the unstable build + Cloudflare plugin
        (final: super: let
          unstable = nixpkgsUnstable.legacyPackages.${system};
        in {
          caddy = unstable.caddy.withPlugins {
            plugins = [ "github.com/caddy-dns/cloudflare@v0.2.5" ];
            # first build will print “got: sha256‑…”; paste that here:
            # hash = "sha256-…";
          };
        })
      ];
    };

    ############################################################################
    # 3) Development shell
    ############################################################################
    devShells.${system}.default = import ./devshell.nix {
      inherit (nixpkgs.legacyPackages.${system}) pkgs;
    };
  };
}
