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

  # PATH for direnv
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

  # CAPI configuration (targeting your local cluster)
  capi = import ./kubenix/stages/capi.nix { inherit pkgs easykubenix; };
  init = import ./kubenix/stages/init.nix { inherit pkgs easykubenix; };
  full = import ./kubenix/stages/full.nix { inherit pkgs easykubenix; };
}
