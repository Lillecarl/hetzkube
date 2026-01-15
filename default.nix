{ ... }@args:
let
  flake =
    let
      lock = builtins.fromJSON (builtins.readFile ./flake.lock);
      flake-compatish = import (builtins.fetchTree lock.nodes.flake-compatish.locked);
    in
    flake-compatish {
      source = ./.;
      overrides = {
        self = ./.;
        nixpkgs = <nixpkgs>;
        nix-csi = /home/lillecarl/Code/nix-csi;
      };
    };

  pkgs = import flake.inputs.nixpkgs {
    config.allowUnfree = true;
    overlays = [
      (import ./pkgs)
    ];
  };
  crossAttrs = {
    "x86_64-linux" = "aarch64-linux";
    "aarch64-linux" = "x86_64-linux";
  };
  pkgsOff = import flake.inputs.nixpkgs {
    config.allowUnfree = true;
    system = crossAttrs.${builtins.currentSystem};
    overlays = [
      (import ./pkgs)
    ];
  };

  kubenix = import ./kubenix {
    inherit pkgs pkgsOff args;
    inherit (flake.inputs) easykubenix nix-csi;
  };
  python = pkgs.python3.withPackages (
    ps: with ps; [
      pkgs.kr8s
      hcloud
    ]
  );
in
flake.impure
// rec {
  inherit pkgs flake kubenix;
  inherit (pkgs) lib;

  # PATH for direnv
  repoenv = pkgs.buildEnv {
    name = "repoenv";
    paths = with pkgs; [
      clusterctl
      cilium-cli
      kubectl
      kubectl-cnpg
      kubelogin-oidc
      kubeseal
      kind
      sops
      age
      doggo
      python
      openssh
      cachix
      yamlfmt
      fluxcd
    ];
  };
}
