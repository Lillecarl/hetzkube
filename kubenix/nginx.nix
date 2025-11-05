{
  config,
  pkgs,
  lib,
  ...
}:
let
  moduleName = "nginx";
  cfg = config.${moduleName};
in
{
  options.${moduleName} = {
    enable = lib.mkEnableOption moduleName;
    namespace = lib.mkOption {
      type = lib.types.str;
      default = "ingress-nginx";
    };
    chart = lib.mkOption {
      type = lib.types.either lib.types.package lib.types.path;
      default = "${
        builtins.fetchTree {
          type = "github";
          owner = "kubernetes";
          repo = "ingress-nginx";
          ref = "helm-chart-4.13.3";
        }
      }/charts/ingress-nginx";
    };
    values = lib.mkOption {
      type = lib.types.anything;
      default = { };
    };
  };
  config = lib.mkIf cfg.enable {
    kubernetes.resources.none.Namespace.${cfg.namespace} = { };
    helm.releases.${moduleName} = {
      inherit (cfg) namespace chart values;
    };
  };
}
