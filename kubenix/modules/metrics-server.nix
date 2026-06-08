{
  config,
  pkgs,
  lib,
  ...
}:
let
  moduleName = "metrics-server";
  cfg = config.${moduleName};
in
{
  options.${moduleName} = {
    enable = lib.mkEnableOption moduleName;
    version = lib.mkOption {
      type = lib.types.nonEmptyStr;
      default = "0.8.1";
    };
    helmValues = lib.mkOption {
      type = lib.types.anything;
      default = { };
    };
  };
  config =
    let
      src = builtins.fetchTree {
        type = "github";
        owner = "kubernetes-sigs";
        repo = "metrics-server";
        ref = "v${cfg.version}";
      };
    in
    lib.mkIf cfg.enable {
      helm.releases.${moduleName} = {
        namespace = "kube-system";
        chart = "${src}/charts/metrics-server";

        values = lib.recursiveUpdate {
          image.tag = lib.mkDefault "v${cfg.version}";
          args = lib.mkDefault [ "--kubelet-insecure-tls" ];
          service.labels = {
            "kubernetes.io/cluster-service" = "true";
            "kubernetes.io/name" = "Metrics-server";
          };
        } cfg.helmValues;
      };
    };
}
