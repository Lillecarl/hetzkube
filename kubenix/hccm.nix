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
    chart = lib.mkOption {
      type = lib.types.either lib.types.package lib.types.path;
      default = "${
        builtins.fetchTree {
          type = "github";
          owner = "hetznercloud";
          repo = "hcloud-cloud-controller-manager";
          ref = "v1.27.0";
        }
      }/chart";
    };
    apiToken = lib.mkOption {
      type = lib.types.str;
    };
    values = lib.mkOption {
      type = lib.types.anything;
      default = { };
    };
  };
  config = lib.mkIf cfg.enable {
    kubernetes.resources.none.Namespace.${cfg.namespace} = { };
    kubernetes.resources.${cfg.namespace}.Secret.hcloud.stringData.token = cfg.apiToken;
    helm.releases.${moduleName} = {
      inherit (cfg) namespace chart values;
    };
  };
}
