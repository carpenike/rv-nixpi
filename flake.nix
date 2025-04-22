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

    # Use nixos-hardware from nixpkgs input for better compatibility
    nixosHardware = inputs.nixpkgs.lib.makeSearchPathOutput "share" "nixos-hardware/raspberry-pi/4";

    commonModules = [
      ./hardware-configuration.nix
      # Import the default module from the nixosHardware path
      (import "${nixosHardware}/default.nix")
      sops-nix.nixosModules.sops
      ./modules/bootstrap-check.nix
      ./modules/canbus.nix
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
