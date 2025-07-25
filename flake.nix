{
  description = "Raspberry Pi 4 Base System for RV CANbus Filtering with SOPS & Impermanence (NixOS 24.11)";

  inputs = {
    nixpkgs           = { url = "nixpkgs/nixos-24.11"; };
    nixpkgsUnstable   = { url = "nixpkgs/nixos-unstable"; };

    nixos-generators  = {
      url = "github:nix-community/nixos-generators";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    sops-nix = {
      url = "github:mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    coachiq = {
      url = "github:carpenike/coachiq";
    };
  };

  outputs = { nixpkgs, nixpkgsUnstable, nixos-generators, sops-nix, coachiq, ... }@inputs:
  let
    system = "aarch64-linux";

    # Fetch nixos-hardware separately
    nixosHardware = fetchTarball {
      url = "https://github.com/NixOS/nixos-hardware/archive/8f44cbb48c2f4a54e35d991a903a8528178ce1a8.tar.gz";
      sha256 = "0glwldwckhdarp6lgv6pia64w4r0c4r923ijq20dcxygyzchy7ai";
    };

    # Overlay to allow missing modules
    allowMissingModulesOverlay = final: super: {
      makeModulesClosure = args:
        super.makeModulesClosure (args // { allowMissing = true; });
    };

    # 1) Import unstable channel once
    unstablePkgs = import nixpkgsUnstable {
      inherit system;
      config.allowUnfree = true;
    };

    # 2) Import stable pkgs, shadowing caddy with plugin-enabled build from unstable
    pkgs = import nixpkgs {
      inherit system;
      config = { allowUnfree = true; };
      overlays = [
        allowMissingModulesOverlay
        (final: prev: {
          caddy = unstablePkgs.caddy.withPlugins {
            # Include Cloudflare DNS provider plugin
            plugins = [ "github.com/caddy-dns/cloudflare@v0.2.1" ];
            hash = "sha256-saKJatiBZ4775IV2C5JLOmZ4BwHKFtRZan94aS5pO90";
          };
        })
      ];
    };

    commonModules = [
      { nixpkgs.overlays = [ allowMissingModulesOverlay ]; }
      ./hardware-configuration.nix
      "${nixosHardware}/raspberry-pi/4"
      sops-nix.nixosModules.sops
      ./modules/bootstrap-check.nix
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
  in
  {
    packages.${system} = {
      # Re-export coachiq package for convenience
      coachiq = coachiq.packages.${system}.coachiq;
      
      # Main SD card image
      sdcard = nixos-generators.nixosGenerate {
        inherit system;
        format = "sd-aarch64";
        modules = commonModules;
      };
    };

    # Use the flake input's lib.nixosSystem, passing our overlaid pkgs via specialArgs
    nixosConfigurations.nixpi = nixpkgs.lib.nixosSystem {
      inherit system pkgs;
      specialArgs = { inherit coachiq; };
      modules = commonModules ++ [
        # Import the coachiq NixOS module
        coachiq.nixosModules.coachiq
        
        # Configure coachiq service
        ./modules/coachiq.nix
      ];
    };

    devShells.${system}.default = pkgs.mkShell {
      buildInputs = [ pkgs.caddy ];
    };
  };
}
