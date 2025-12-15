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
      includeCRDs = true;

      chart = "${
        builtins.fetchTree {
          type = "github";
          owner = "stevehipwell";
          repo = "helm-charts";
          ref = "main";
        }
      }/charts/vertical-pod-autoscaler";

      values = lib.recursiveUpdate {
      } cfg.helmValues;
    };
    kubernetes.apiMappings.VerticalPodAutoscaler = "autoscaling.k8s.io/v1";
    kubernetes.namespacedMappings.VerticalPodAutoscaler = true;
  };
}
