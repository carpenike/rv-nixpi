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

    # Optional app input
    # rvc-app.url = "github:yourusername/rvc-app";
  };

  outputs = { self, nixpkgs, nixos-generators, sops-nix, ... }@inputs:
  let
    system = "aarch64-linux";

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
      "${nixosHardware}/raspberry-pi/4"
      sops-nix.nixosModules.sops
      ./modules/bootstrap-check.nix
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
      # (./modules/systemPackages.nix { rvcApp = inputs.rvc-app; })
    ];

  in {
    packages.${system}.sdcard = nixos-generators.nixosGenerate {
      system = system;
      format = "sd-aarch64";
      modules = commonModules;
    };

    nixosConfigurations.nixpi = nixpkgs.lib.nixosSystem {
      system = system;
      modules = commonModules;
    };

    devShells.${system}.default = import ./devshell.nix {
    inherit (nixpkgs.legacyPackages.${system}) pkgs;
  };
  };
}
