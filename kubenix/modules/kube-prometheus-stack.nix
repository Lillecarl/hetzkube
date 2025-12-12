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
      default = moduleName;
    };
    version = lib.mkOption {
      type = lib.types.str;
      default = "80.2.2";
    };
    sha256 = lib.mkOption {
      type = lib.types.str;
      default = "sha256-L1ylQ55+WIyVbfv5mF3JBjZ6FfwkFFg7YazEHB6LsNU=";
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
        prometheusOperator.admissionWebhooks.certManager.enabled = true;
      } cfg.helmValues;
    };
  };
}
