{ pkgs, ... }:
{
  kluctl = {
    deployment.vars = [ { file = "secrets/all.yaml"; } ];
    files."secrets/all.yaml" = builtins.readFile ../../secrets/all.yaml;
    preDeployScript =
      pkgs.writeScriptBin "preDeployScript" # bash
        ''
          #! ${pkgs.runtimeShell}
          set -euo pipefail
          set -x
          export NIX_SSHOPTS="-i $PWD/tmp/ed25519-hetzkube"
          nix store sign --key-file ./tmp/lillecarl-1 --recursive "$1"
          nix --store daemon copy --substitute-on-destination --no-check-sigs --to ssh-ng://nixbuild.lillecarl.com "$1" -v || true
        '';

  };
}
