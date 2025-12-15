{
  config,
  pkgs,
  lib,
  ...
}:
let
  moduleName = "vertical-pod-autoscaler";
  cfg = config.${moduleName};
in
{
  options.${moduleName} = {
    enable = lib.mkEnableOption moduleName;
    namespace = lib.mkOption {
      type = lib.types.str;
      default = "kube-system";
    };
    version = lib.mkOption {
      type = lib.types.str;
      default = "1.5";
    };
    helmValues = lib.mkOption {
      type = lib.types.anything;
      default = { };
    };
  };
  config = lib.mkIf cfg.enable {
    kubernetes.resources.none.Namespace.${cfg.namespace} = { };
    helm.releases.${moduleName} = {
      namespace = cfg.namespace;

      chart = "${
        builtins.fetchTree {
          type = "github";
          owner = "kubernetes";
          repo = "autoscaler";
          # ref = "vpa-release-${cfg.version}";
          ref = "master";
        }
      }/vertical-pod-autoscaler/charts/vertical-pod-autoscaler";

      values = lib.recursiveUpdate {
      } cfg.helmValues;
    };
  };
}
