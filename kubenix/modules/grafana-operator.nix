{
  config,
  pkgs,
  lib,
  ...
}:
let
  moduleName = "grafana-operator";
  cfg = config.${moduleName};
in
{
  options.${moduleName} = {
    enable = lib.mkEnableOption moduleName;
    version = lib.mkOption {
      type = lib.types.nonEmptyStr;
      default = "*";
    };
    namespace = lib.mkOption {
      type = lib.types.nonEmptyStr;
      default = "grafana";
    };
  };
  config = lib.mkIf cfg.enable {
    kubernetes.resources.none.Namespace.${cfg.namespace} = { };
    kubernetes.resources.${cfg.namespace} = {
      HelmRepository.grafana = {
        spec = {
          type = "oci";
          interval = "1h";
          url = "oci://ghcr.io/grafana/helm-charts";
        };
      };
      HelmRelease.grafana-operator = {
        spec = {
          interval = "1h";
          chart = {
            spec = {
              chart = "grafana-operator";
              version = cfg.version;
              sourceRef = {
                kind = "HelmRepository";
                name = "grafana";
                namespace = cfg.namespace;
              };
            };
          };
        };
      };
    };
    kubernetes.apiMappings = {
      GrafanaAlertRuleGroup = "grafana.integreatly.org/v1beta1";
      GrafanaContactPoint = "grafana.integreatly.org/v1beta1";
      GrafanaDashboard = "grafana.integreatly.org/v1beta1";
      GrafanaDatasource = "grafana.integreatly.org/v1beta1";
      GrafanaFolder = "grafana.integreatly.org/v1beta1";
      GrafanaLibraryPanel = "grafana.integreatly.org/v1beta1";
      GrafanaMuteTiming = "grafana.integreatly.org/v1beta1";
      GrafanaNotificationPolicy = "grafana.integreatly.org/v1beta1";
      GrafanaNotificationPolicyRoute = "grafana.integreatly.org/v1beta1";
      GrafanaNotificationTemplate = "grafana.integreatly.org/v1beta1";
      Grafana = "grafana.integreatly.org/v1beta1";
      GrafanaServiceAccount = "grafana.integreatly.org/v1beta1";
    };
  };
}
