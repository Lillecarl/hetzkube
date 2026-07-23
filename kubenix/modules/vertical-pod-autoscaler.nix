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

    helm.releases.vertical-pod-autoscaler = {
      namespace = cfg.namespace;
      chart = builtins.fetchTree {
        type = "tarball";
        url = "https://github.com/stevehipwell/helm-charts/releases/download/vertical-pod-autoscaler-${cfg.version}/vertical-pod-autoscaler-${cfg.version}.tgz";
      };
      values = lib.recursiveUpdate { } cfg.helmValues;
      # CRDs live in the chart's special `crds/` dir, which `helm template`
      # skips unless asked -- without them the VerticalPodAutoscaler kind
      # doesn't exist at all (this was previously installed by Flux's
      # HelmRelease install.crds="CreateReplace").
      includeCRDs = true;
    };
    kubernetes.apiMappings.VerticalPodAutoscaler = "autoscaling.k8s.io/v1";
    kubernetes.namespacedMappings.VerticalPodAutoscaler = true;
  };
}
