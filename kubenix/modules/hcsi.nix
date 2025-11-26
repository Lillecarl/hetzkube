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
    version = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = "2.18.2";
    };
  };
  config = lib.mkIf cfg.enable {
    importyaml.${moduleName} = {
      src = "https://raw.githubusercontent.com/hetznercloud/csi-driver/v${cfg.version}/deploy/kubernetes/hcloud-csi.yml";
      overrideNamespace = cfg.namespace;
    };
    kubernetes.resources.none.Namespace.${cfg.namespace} = { };
    kubernetes.resources.${cfg.namespace}.Secret.hcloud.stringData.token = cfg.apiToken;
    # Override which namespace the role should bind to
    kubernetes.resources.none.ClusterRoleBinding.hcloud-csi-controller.subjects.hcloud-csi-controller.namespace =
      lib.mkForce cfg.namespace;
  };
}
