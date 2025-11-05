# Deploy Hetzner Cloud Controller Manager
{
  config,
  pkgs,
  lib,
  ...
}:
let
  moduleName = "hccm";
  cfg = config.${moduleName};
in
{
  options.${moduleName} = {
    enable = lib.mkEnableOption moduleName;
    namespace = lib.mkOption {
      type = lib.types.str;
      default = moduleName;
    };
    apiToken = lib.mkOption {
      type = lib.types.str;
    };
    helmValues = lib.mkOption {
      type = lib.types.anything;
      default = { };
    };
  };
  config = lib.mkIf cfg.enable {
    kubernetes.resources.none.Namespace.${cfg.namespace} = { };
    kubernetes.resources.${cfg.namespace}.Secret.hcloud.stringData.token = cfg.apiToken;
    helm.releases.${moduleName} = {
      namespace = cfg.namespace;

      chart = "${
        builtins.fetchTree {
          type = "github";
          owner = "hetznercloud";
          repo = "hcloud-cloud-controller-manager";
          ref = "v1.27.0";
        }
      }/chart";

      values = { } // cfg.helmValues;
    };
  };
}
