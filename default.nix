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

  osOptions =
    let
      inherit (flake.impure.nixosConfigurations."image-${pkgs.system}") options;
      optionsList = builtins.filter (v: v.visible && !v.internal) (
        pkgs.lib.optionAttrSetToDocList options
      );
    in
    pkgs.writeText "osOptions" (builtins.toJSON optionsList);

  knOptions =
    let
      inherit (kubenixStaged.eval) options;
      optionsList = builtins.filter (v: v.visible && !v.internal) (
        pkgs.lib.optionAttrSetToDocList options
      );
    in
    pkgs.writeText "osOptions" (builtins.toJSON optionsList);

  optnixConfig = (pkgs.formats.toml { }).generate "optnix.toml" {
    min_score = 3;
    debounce_time = 25;
    default_scope = "";
    formatter_cmd = "nixfmt";
    scopes.hkos = {
      description = "NixOS options";
      options-list-file = toString osOptions;
    };
    scopes.hkkn = {
      description = "easykubenix options";
      options-list-file = toString knOptions;
    };
  };

  kubenix = import ./kubenix {
    inherit pkgs args;
    inherit (flake.inputs) easykubenix nix-csi;
  };
  kubenixStaged = import ./kubenix {
    inherit pkgs;
    inherit (flake.inputs) easykubenix nix-csi;
    args.stage = "init";
  };
in
flake.impure
// rec {
  inherit pkgs;
  inherit (pkgs) lib;
  inherit kubenix;

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
      (writeScriptBin "optnix" # bash
        ''
          exec ${lib.getExe optnix} --config ${optnixConfig} $@
        ''
      )
    ];
  };
}
