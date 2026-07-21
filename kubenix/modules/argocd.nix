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
    importyaml.argocd.src = "https://raw.githubusercontent.com/argoproj/argo-cd/v${cfg.version}/manifests/install.yaml";
  };
}
