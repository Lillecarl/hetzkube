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
    kubernetes = {
      apiMappings = {
        AlertmanagerConfig = "monitoring.coreos.com/v1alpha1";
        Alertmanager = "monitoring.coreos.com/v1";
        PodMonitor = "monitoring.coreos.com/v1";
        Probe = "monitoring.coreos.com/v1";
        PrometheusAgent = "monitoring.coreos.com/v1alpha1";
        Prometheus = "monitoring.coreos.com/v1";
        PrometheusRule = "monitoring.coreos.com/v1";
        ScrapeConfig = "monitoring.coreos.com/v1alpha1";
        ServiceMonitor = "monitoring.coreos.com/v1";
        ThanosRuler = "monitoring.coreos.com/v1";
      };
      namespacedMappings = {
        AlertmanagerConfig = true;
        Alertmanager = true;
        PodMonitor = true;
        Probe = true;
        PrometheusAgent = true;
        Prometheus = true;
        PrometheusRule = true;
        ScrapeConfig = true;
        ServiceMonitor = true;
        ThanosRuler = true;
      };
    };
  };
}
