{
  description = "Raspberry Pi 4 Base System for RV CANbus Filtering with SOPS & Impermanence (NixOS 24.11)";

  inputs = {
    nixpkgs.url = "nixpkgs/nixos-24.11";

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
      # inputs.nixpkgs.follows = "nixpkgs"; # Removed to allow rvc2api to use its own nixpkgs input
    };
  };

  outputs = { self, nixpkgs, nixos-generators, sops-nix, rvc2api, ... }@inputs:
  let
    system = "aarch64-linux";

    # Revert to fetching nixos-hardware separately
    nixosHardware = fetchTarball {
      url = "https://github.com/NixOS/nixos-hardware/archive/8f44cbb48c2f4a54e35d991a903a8528178ce1a8.tar.gz";
      sha256 = "0glwldwckhdarp6lgv6pia64w4r0c4r923ijq20dcxygyzchy7ai";
    };

    # Re-add the overlay to suppress module errors
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
      ./modules/caddy.nix # Added Caddy module
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
      # ./modules/rvc-config.nix # Removed: Handled by rvc.nix
      # ./modules/rvc-debug-tools.nix # Removed: Handled by rvc.nix
      # ./modules/rvc-console.nix # Removed: Handled by rvc.nix
      ./modules/rvc.nix # Added: Parent module for RVC features
      # (./modules/systemPackages.nix { rvcApp = inputs.rvc-app; })
    ];

  in {
    packages.${system} = {
      # Use the defaultPackage from the rvc2api flake input for the current system
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
        # <<< Add your settings here >>>
        ({ config, ... }: { # Wrap the anonymous module in a function that takes config
          services.rvc.console.enable = true;    # Enable the console app
          services.rvc.debugTools.enable = true; # Enable the debug tools
          # Enable the new FastAPI CANbus API
          services.rvc2api.enable      = true;
          services.rvc2api.package     = inputs.rvc2api.defaultPackage.${system};
          services.rvc2api.specFile    = "/etc/nixos/files/rvc.json";
          services.rvc2api.mappingFile = "/etc/nixos/files/device_mapping.yml";
          services.rvc2api.channels    = [ "can0" "can1" ];
          services.rvc2api.bustype     = "socketcan";
          services.rvc2api.bitrate     = 500000;

          # Enable Caddy reverse proxy
          services.rvcaddy = {
            enable = false;
            hostname = "rvc.holtel.io";
            proxyTarget = "http://localhost:8000"; # rvc2api default
            cloudflareApiTokenFile = config.sops.secrets.cloudflare_api_token.path;
          };

          # Ensure Caddy user can access the sops-managed secret
          users.users.caddy.extraGroups = [ config.sops.secrets.cloudflare_api_token.group ];
        })
      ];
    };

    devShells.${system}.default = import ./devshell.nix {
      inherit (nixpkgs.legacyPackages.${system}) pkgs;
    };
  };
}
