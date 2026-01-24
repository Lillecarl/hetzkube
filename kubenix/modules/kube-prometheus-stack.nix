{
  config,
  pkgs,
  lib,
  ...
}:
let
  moduleName = "kube-prometheus-stack";
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
      default = "81.2.2";
    };
    hostname = lib.mkOption {
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
        url = "https://github.com/prometheus-community/helm-charts/releases/download/kube-prometheus-stack-${cfg.version}/kube-prometheus-stack-${cfg.version}.tgz";
      };

      values = lib.recursiveUpdate {
        crds.enabled = true;
        prometheusOperator.admissionWebhooks.certManager.enabled = config.cert-manager.enable;
      } cfg.helmValues;
    };
  };
}
