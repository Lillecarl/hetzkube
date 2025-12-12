{ pkgs, ... }:
{
  kluctl = {
    deployment.vars = [ { file = "secrets/all.yaml"; } ];
    files."secrets/all.yaml" = builtins.readFile ../../secrets/all.yaml;
    # Disable templating for default resource project
    files."default/.templateignore" = "*";
    # Put priorities on resources, this also excludes the from the templateignore above
    preDeployScript =
      pkgs.writeScriptBin "preDeployScript" # bash
        ''
          #! ${pkgs.runtimeShell}
          set -euo pipefail
          set -x
          export NIX_SSHOPTS="-i $PWD/tmp/ed25519-hetzkube"
          nix copy --substitute-on-destination --no-check-sigs --from local?read-only=true --to ssh-ng://nix@nixbuild.lillecarl.com?port=2222 "$1" -v || true
          # cachix push nix-csi "$1"
        '';

  };
}
