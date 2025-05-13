{
  description = "Raspberry Pi 4 Base System for RV CANbus Filtering with SOPS & Impermanence (NixOS 24.11)";

  inputs = {
    nixpkgs.url = "nixpkgs/nixos-24.11";
    nixpkgsUnstable.url = "nixpkgs/nixos-unstable";

    nixos-generators = {
      url = "github:nix-community/nixos-generators";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    sops-nix = {
      url = "github:mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    rvc2api = {
      url = "github:carpenike/rvc2api";
    };
  };

  outputs = { nixpkgs, nixos-generators, sops-nix, ... }@inputs:
  let
    system = "aarch64-linux";

    # Revert to fetching nixos-hardware separately
    nixosHardware = fetchTarball {
      url = "https://github.com/NixOS/nixos-hardware/archive/8f44cbb48c2f4a54e35d991a903a8528178ce1a8.tar.gz";
      sha256 = "0glwldwckhdarp6lgv6pia64w4r0c4r923ijq20dcxygyzchy7ai";
    };

    allowMissingModulesOverlay = final: super: {
      makeModulesClosure = args:
        super.makeModulesClosure (args // { allowMissing = true; });
    };

    commonModules = [
      { nixpkgs.overlays = [ allowMissingModulesOverlay ]; }
      ./hardware-configuration.nix
      # Use the fetched nixos-hardware path
      "${nixosHardware}/raspberry-pi/4"
      sops-nix.nixosModules.sops
      ./modules/bootstrap-check.nix
      # ./modules/caddy.nix
      ./modules/canbus.nix
      ./modules/cloudflared.nix
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
    packages.${system} = {
      rvc2api = inputs.rvc2api.defaultPackage.${system};
      sdcard = nixos-generators.nixosGenerate {
        system = system;
        format = "sd-aarch64";
        modules = commonModules;
      };
    };

    nixosConfigurations.nixpi = nixpkgs.lib.nixosSystem {
      system = system;
      modules = commonModules ++ [
        inputs.rvc2api.nixosModules.rvc2api
        ({ ... }: {
          rvc2api.settings = {
            canbus = {
              channels = [ "can0" "can1" ];
              bustype = "socketcan";
              bitrate = 500000;
            };
            # rvcSpecPath = "/etc/nixos/files/rvc.json";
            # deviceMappingPath = "/etc/nixos/files/device_mapping.yml";
            pushover = {
              enable = false;
              # apiToken = "...";
              # userKey = "...";
            };
            uptimerobot = {
              enable = false;
              # apiKey = "...";
            };
          };
          # ...other service configs...
          services.rvc.console.enable = true;
          services.rvc.debugTools.enable = true;
          services.rvcCloudflared = {
            enable = true;
            hostname = "rvc.holtel.io";
            service = "http://localhost:8000";
          };
          # services.rvcCaddy = {
          #   enable = false;
          #   hostname = "rvc.holtel.io";
          #   backendPort = 80;
          #   email = "ryan@ryanholt.net";
          # };
        })
      ];
    };

    devShells.${system}.default = import ./devshell.nix {
      inherit (nixpkgs.legacyPackages.${system}) pkgs;
    };
  };
}
