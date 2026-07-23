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
        nixpkgs = /etc/nixpkgs;
        nix-csi = /home/lillecarl/Code/nix-csi;
        easykubenix = /home/lillecarl/Code/easykubenix;
        nanopynix = /home/lillecarl/Code/nanopynix;
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
  nanopynix = import flake.inputs.nanopynix { inherit pkgs; };
  # pynix's own `ekn` extra (see nanopynix/pynix/package.nix) bundles
  # easykubenix's ekn CLI into pynix, so `pynix ekn deploy ...` replaces the
  # old standalone `kubenix.passthru.ekn` invocation. This is the
  # reproducible, immutable build. `pynixDevEnv` is the editable,
  # hot-reloading counterpart (see nanopynix/nix/dev-env.nix) -- .envrc
  # puts it on PATH directly (not folded into repoenv's buildEnv: its own
  # bin/python3 collides with repoenv's separate `python` env).
  inherit (nanopynix) pynix pynixDevEnv;
  python = pkgs.python3.withPackages (
    ps: with ps; [
      pkgs.kr8s
      hcloud
    ]
  );
in
flake.impure
// rec {
  inherit
    pkgs
    flake
    kubenix
    pynix
    pynixDevEnv
    ;
  inherit (pkgs) lib;

  shell = pkgs.mkShell {
    packages = with pkgs; [
      pynixDevEnv
      clusterctl
      cilium-cli
      kubectl
      kubernetes-helm
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
      victorialogs
    ];
  };
}
