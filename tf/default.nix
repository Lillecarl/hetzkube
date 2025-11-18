let
  root = import ../. { };
  inherit (root) pkgs;
  inherit (pkgs) lib;
  terranix = import "${root.flake.inputs.terranix}/core" {
    inherit pkgs;
    terranix_config = {
      imports = [
        ./terranix.nix
      ];
    };
  };
  tnJSON = pkgs.writeText "tnJSON" (builtins.toJSON terranix.config);
in
{
  inherit terranix;
  inherit pkgs;
  run =
    pkgs.writeScriptBin "terranix" # bash
      ''
        #! ${pkgs.runtimeShell}
        set -euo pipefail
        set -x
        cat ${tnJSON} > config.tf.json
        ${lib.getExe pkgs.opentofu} $@
      '';
}
