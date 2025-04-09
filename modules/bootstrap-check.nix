{ lib, ... }:

let
  bootstrapKey = builtins.getEnv "AGE_BOOTSTRAP_KEY";

  # Check if we are building the sdcard image
  isImageBuild = builtins.trace "NIX_BUILD_TOP: ${builtins.getEnv "NIX_BUILD_TOP"}" (builtins.getEnv "NIX_BUILD_TOP" != "");

in
{
  config = lib.mkIf isImageBuild {
    assertions = [
      {
        assertion = bootstrapKey != "";
        message = ''
          🔐 AGE_BOOTSTRAP_KEY environment variable is required to build the image.
          Example:
            AGE_BOOTSTRAP_KEY="$(cat secrets/age.key)" nix build .#packages.aarch64-linux.sdcard
        '';
      }
    ];
  };
}
