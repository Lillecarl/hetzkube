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
      default = "80.13.3";
    };
    sha256 = lib.mkOption {
      type = lib.types.str;
      default = lib.fakeHash;
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

      chart = pkgs.fetchHelm {
        chart = "kube-prometheus-stack";
        repo = "https://prometheus-community.github.io/helm-charts";
        inherit (cfg) version sha256;
      };

      values = lib.recursiveUpdate {
        crds.enabled = true;
        prometheusOperator.admissionWebhooks.certManager.enabled = config.cert-manager.enable;
      } cfg.helmValues;
    };
  };
}
