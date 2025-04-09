{ lib, ... }:

let
  bootstrapKey = builtins.getEnv "AGE_BOOTSTRAP_KEY";

  # Only assert during a top-level system image build
  isImageBuild =
    # This is true during `nix build .#packages.aarch64-linux.sdcard`
    lib.inPureEvalMode;
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
