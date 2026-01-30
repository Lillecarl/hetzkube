{
  config,
  pkgs,
  lib,
  ...
}:
let
  moduleName = "alloy";
  cfg = config.${moduleName};
in
{
  options.${moduleName} = {
    enable = lib.mkEnableOption moduleName;
    namespace = lib.mkOption {
      type = lib.types.str;
      default = "observability";
    };
    version = lib.mkOption {
      type = lib.types.str;
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
      noHooks = true;

      chart = builtins.fetchTree {
        type = "tarball";
        url = "https://github.com/grafana/helm-charts/releases/download/alloy-${cfg.version}/alloy-${cfg.version}.tgz";
      };

      values = lib.recursiveUpdate {

      } cfg.helmValues;
    };
    kubernetes = {
      apiMappings = {
        # AlertmanagerConfig = "monitoring.coreos.com/v1alpha1";
      };
      namespacedMappings = {
        # AlertmanagerConfig = true;
      };
    };
  };
}
