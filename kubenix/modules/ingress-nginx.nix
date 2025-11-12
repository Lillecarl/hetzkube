{
  config,
  pkgs,
  lib,
  ...
}:
let
  moduleName = "ingress-nginx";
  cfg = config.${moduleName};
in
{
  options.${moduleName} = {
    enable = lib.mkEnableOption moduleName;
    namespace = lib.mkOption {
      type = lib.types.str;
      default = moduleName;
    };
    values = lib.mkOption {
      type = lib.types.anything;
      default = { };
    };
  };
  config = lib.mkIf cfg.enable {
    kubernetes.resources.none.Namespace.${cfg.namespace} = { };
    helm.releases.${moduleName} = {
      chart = "${
        builtins.fetchTree {
          type = "github";
          owner = "kubernetes";
          repo = "ingress-nginx";
          ref = "helm-chart-4.13.3";
        }
      }/charts/ingress-nginx";
      inherit (cfg) namespace values;
    };
  };
}
