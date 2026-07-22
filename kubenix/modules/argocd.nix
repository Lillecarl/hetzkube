{
  config,
  pkgs,
  lib,
  ...
}:
let
  moduleName = "argocd";
  cfg = config.${moduleName};
in
{
  options.${moduleName} = {
    enable = lib.mkEnableOption moduleName;
    version = lib.mkOption {
      type = lib.types.nonEmptyStr;
    };
  };
  config = lib.mkIf cfg.enable {
    # Upstream install.yaml deliberately omits this (their docs expect
    # `kubectl create namespace argocd` first) -- declare it so the
    # namespace is part of kubernetes.generated like everything else,
    # instead of only existing because bootstrap-argocd.py creates it by
    # hand before applying anything else. Routed to "bootstrap" like the
    # rest of ArgoCD's own install objects (see gitops.nix's
    # importyaml.argocd.overrides) -- it needs to exist before ArgoCD can
    # run, so it belongs in the same one-time bootstrap apply, not synced
    # in later via "everything".
    kubernetes.resources.none.Namespace.argocd.ekn.gitOpsTarget = "bootstrap";
    importyaml.argocd.src = "https://raw.githubusercontent.com/argoproj/argo-cd/v${cfg.version}/manifests/install.yaml";
  };
}
