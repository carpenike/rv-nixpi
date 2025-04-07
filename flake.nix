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
    # Your custom rvc application lives in its own repository
    # rvc-app.url = "github:yourusername/rvc-app";
  };

  outputs = { self, nixpkgs, nixos-generators, sops-nix, ... }:
  # outputs = { self, nixpkgs, nixos-generators, sops-nix, rvc-app, ... }:
  let
    system = "aarch64-linux";
  in {
    packages.${system}.sdcard = nixos-generators.nixosGenerate {
      system = system;
      format = "sd-aarch64";
      modules = [
        ./hardware-configuration.nix
        (let nixosHardwareVersion = "a3f63440fcfb280d7c9c5dd83f6cc95051867b17";
        in "${fetchTarball "https://github.com/NixOS/nixos-hardware/archive/${nixosHardwareVersion}.tar.gz"}/raspberry-pi/4")
        ./modules/boot.nix
        ./modules/networking.nix
        ./modules/users.nix
        ./modules/services.nix
        ./modules/impermanence.nix
        ./modules/secrets.nix
        ./modules/ssh.nix
        ./modules/sudo.nix
        (./modules/systemPackages.nix )#{ rvcApp = rvc-app; })
      ];
    };
  };
}
