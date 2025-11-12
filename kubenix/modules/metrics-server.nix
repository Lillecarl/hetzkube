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
    helmAttrs = lib.mkOption {
      type = lib.types.anything;
      default = { };
    };
  };
  config = lib.mkIf cfg.enable {
    helm.releases.${moduleName} = {
      namespace = "kube-system";
      chart = "${
        builtins.fetchTree {
          type = "github";
          owner = "kubernetes-sigs";
          repo = "metrics-server";
          ref = "v0.8.0";
        }
      }/charts/metrics-server";

      values = {
        # apiService.insecureSkipTLSVerify = false;
        # tls.type = "cert-manager";
        args = [ "--kubelet-insecure-tls" ];
      }
      // cfg.helmAttrs;
    };
  };
}
