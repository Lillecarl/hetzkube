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
      type = lib.types.nonEmptyStr;
    };
    helmValues = lib.mkOption {
      type = lib.types.anything;
      default = { };
    };
  };
  config = lib.mkIf cfg.enable {
    kubernetes.resources.none.Namespace.${cfg.namespace} = { };

    kubernetes.resources.${cfg.namespace} = {
      HelmRepository.stevehipwell = {
        spec = {
          interval = "1h";
          url = "https://stevehipwell.github.io/helm-charts";
        };
      };
      HelmRelease.vertical-pod-autoscaler = {
        spec = {
          chart = {
            spec = {
              chart = "vertical-pod-autoscaler";
              version = cfg.version;
              sourceRef = {
                kind = "HelmRepository";
                name = "stevehipwell";
                namespace = cfg.namespace;
              };
            };
          };
          values = lib.recursiveUpdate { } cfg.helmValues;
          interval = "1h";
          driftDetection = {
            mode = "enabled";
            ignore = [ ];
          };
        };
      };
    };
    kubernetes.apiMappings.VerticalPodAutoscaler = "autoscaling.k8s.io/v1";
    kubernetes.namespacedMappings.VerticalPodAutoscaler = true;
  };
}
