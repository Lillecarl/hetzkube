{
  config,
  lib,
  ...
}:
let
  moduleName = "hcsi";
  cfg = config.${moduleName};
in
{
  options.${moduleName} = {
    enable = lib.mkEnableOption moduleName;
    namespace = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = moduleName;
    };
    apiToken = lib.mkOption {
      type = lib.types.str;
    };
    url = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = "https://raw.githubusercontent.com/hetznercloud/csi-driver/v2.17.0/deploy/kubernetes/hcloud-csi.yml";
    };
  };
  config = lib.mkIf cfg.enable {
    importyaml.${moduleName} = {
      src = cfg.url;
      overrideNamespace = cfg.namespace;
    };
    kubernetes.resources.none.Namespace.${cfg.namespace} = { };
    kubernetes.resources.${cfg.namespace}.Secret.hcloud.stringData.token = cfg.apiToken;
    # Override which namespace the role should bind to
    kubernetes.resources.none.ClusterRoleBinding.hcloud-csi-controller.subjects.hcloud-csi-controller.namespace= lib.mkForce cfg.namespace;
  };
}
