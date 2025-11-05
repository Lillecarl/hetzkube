let
  flake =
    let
      lockFile = builtins.readFile ./flake.lock;
      lockAttrs = builtins.fromJSON lockFile;
      fcLockInfo = lockAttrs.nodes.flake-compatish.locked;
      fcSrc = builtins.fetchTree fcLockInfo;
      flake-compatish = import fcSrc;
    in
    flake-compatish ./.;

  pkgs = import flake.inputs.nixpkgs {
    overlays = [
      (import ./pkgs)
    ];
  };
  easykubenix =
    let
      path = /home/lillecarl/Code/easykubenix;
    in
    if builtins.pathExists path then
      import path
    else
      import (
        builtins.fetchTree {
          type = "github";
          owner = "lillecarl";
          repo = "easykubenix";
        }
      );
in
flake.impure
// rec {
  inherit pkgs;
  inherit (pkgs) lib;
  repoenv = pkgs.buildEnv {
    name = "repoenv";
    paths = with pkgs; [
      clusterctl
      kubectl
      kubelogin-oidc
      kind
      sops
      age
      doggo
    ];
  };
  capi = import ./capi.nix { inherit pkgs easykubenix; };
}
