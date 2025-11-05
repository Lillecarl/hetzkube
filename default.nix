{ ... }@args:
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

  easykubenix = import flake.inputs.easykubenix;
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

  kubenix = import ./kubenix { inherit pkgs easykubenix args; };
}
