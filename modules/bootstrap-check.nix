{ lib, ... }:

let
  bootstrapKey = builtins.getEnv "AGE_BOOTSTRAP_KEY";
in
{
  config = lib.mkIf (lib.inPureEvalMode or false) {
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
