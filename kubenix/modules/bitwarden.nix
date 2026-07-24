{
  config,
  pkgs,
  lib,
  ...
}:
let
  moduleName = "bitwarden";
  cfg = config.${moduleName};
in
{
  options.${moduleName} = {
    enable = lib.mkEnableOption moduleName;
    version = lib.mkOption {
      type = lib.types.nonEmptyStr;
      default = "1.1.0";
    };
    helmValues = lib.mkOption {
      type = lib.types.anything;
      default = { };
    };
    secretMapping = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
    };
  };
  config =
    let
      src = builtins.fetchTree {
        type = "github";
        owner = "bitwarden";
        repo = "helm-charts";
        ref = "sm-operator-${cfg.version}";
      };
    in
    lib.mkIf cfg.enable {
      helm.releases.${moduleName} = {
        namespace = "kube-system";
        chart = "${src}/charts/sm-operator";

        values = lib.recursiveUpdate { } cfg.helmValues;
      };
      kubernetes.apiMappings.BitwardenSecret = "k8s.bitwarden.com/v1";
      kubernetes.namespacedMappings.BitwardenSecret = true;
    };
}
