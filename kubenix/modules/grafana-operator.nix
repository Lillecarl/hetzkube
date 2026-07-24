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
      default = "5.24.0";
    };
    # Chart is only published via OCI (oci://ghcr.io/grafana/helm-charts), no
    # plain https tarball mirror -- unlike builtins.fetchTree's "tarball"
    # fetcher used elsewhere, fetchHelm's `helm fetch` needs a fixed
    # outputHash pinned per version, so this must be updated by hand
    # (`nix-build` the derivation with a wrong hash and copy the "got:"
    # value) whenever `version` changes.
    chartHash = lib.mkOption {
      type = lib.types.nonEmptyStr;
      default = "sha256-jULnmFaxi3gsWbCnE26FfML6MOqQ60QCpMuOoSv0hdw=";
    };
    namespace = lib.mkOption {
      type = lib.types.nonEmptyStr;
      default = "grafana";
    };
  };
  config = lib.mkIf cfg.enable {
    kubernetes.resources.none.Namespace.${cfg.namespace} = { };
    helm.releases.grafana-operator = {
      namespace = cfg.namespace;
      chart = pkgs.fetchHelm {
        chart = "grafana-operator";
        chartUrl = "oci://ghcr.io/grafana/helm-charts/grafana-operator";
        version = cfg.version;
        sha256 = cfg.chartHash;
      };
      # Chart defaults to crds.immutable=true (CRDs live in the special
      # `crds/` dir, which `helm template` skips unless asked). Flux's
      # HelmRelease installed them anyway (install.crds="CreateReplace" in
      # flux.nix's transformer); the local-render equivalent is includeCRDs.
      includeCRDs = true;
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
