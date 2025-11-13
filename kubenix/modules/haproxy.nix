{
  config,
  pkgs,
  lib,
  ...
}:
let
  moduleName = "haproxy";
  cfg = config.${moduleName};
in
{
  options.${moduleName} = {
    enable = lib.mkEnableOption moduleName;
    namespace = lib.mkOption {
      type = lib.types.str;
      default = moduleName;
    };
    values = lib.mkOption {
      type = lib.types.anything;
      default = { };
    };
  };
  config = lib.mkIf cfg.enable {
    kubernetes.resources.none.Namespace.${cfg.namespace} = { };
    helm.releases.${moduleName} = {
      chart = "${
        builtins.fetchTree {
          type = "github";
          owner = "haproxytech";
          repo = "helm-charts";
          ref = "kubernetes-ingress-1.46.1";
        }
      }/kubernetes-ingress";
      inherit (cfg) namespace values;
    };
  };
}
