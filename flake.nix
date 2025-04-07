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

    # rvc-app.url = "github:yourusername/rvc-app";
  };

  outputs = { self, nixpkgs, nixos-generators, sops-nix, ... }:
  let
    system = "aarch64-linux";

    nixosHardware = fetchTarball {
      url = "https://github.com/NixOS/nixos-hardware/archive/a3f63440fcfb280d7c9c5dd83f6cc95051867b17.tar.gz";
      sha256 = "sha256:0ay6mqbyjig6yksyg916dkz72p2n3lbzryxhvlx8ax4r0564r7fd";
    };
  in {
    packages.${system}.sdcard = nixos-generators.nixosGenerate {
      system = system;
      format = "sd-aarch64";
      modules = [
        ./hardware-configuration.nix
        "${nixosHardware}/raspberry-pi/4"

        ./modules/boot.nix
        ./modules/networking.nix
        ./modules/users.nix
        ./modules/services.nix
        ./modules/impermanence.nix
        ./modules/secrets.nix
        ./modules/ssh.nix
        ./modules/sudo.nix

        ./modules/systemPackages.nix
        # If you later re-enable rvcApp:
        # (./modules/systemPackages.nix { rvcApp = rvc-app; })
      ];
    };
  };
}
