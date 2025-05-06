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
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, nixos-generators, sops-nix, rvc2api, ... }@inputs:
  let
    system = "aarch64-linux";
    pkgs   = nixpkgs.legacyPackages.${system};

    # Build the rvc2api Python package
    rvc2api = pkgs.python3Packages.buildPythonPackage {
      pname = "rvc2api";
      # version = "0.1.0"; # Removed: Let buildPythonPackage read from pyproject.toml
      src   = rvc2api;
      # It will pick up pyproject.toml for deps
    };

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
      rvc2api = rvc2api;
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
        {
          services.rvc.console.enable = true;    # Enable the console app
          services.rvc.debugTools.enable = true; # Enable the debug tools
          # Enable the new FastAPI CANbus API
          services.rvc2api.enable      = true;
          services.rvc2api.package     = rvc2api;
          services.rvc2api.specFile    = "/etc/nixos/files/rvc.json";
          services.rvc2api.mappingFile = "/etc/nixos/files/device_mapping.yml";
          services.rvc2api.channels    = [ "can0" "can1" ];
          services.rvc2api.bustype     = "socketcan";
          services.rvc2api.bitrate     = 500000;
        }
      ];
    };

    devShells.${system}.default = import ./devshell.nix {
      inherit (nixpkgs.legacyPackages.${system}) pkgs;
    };
  };
}
