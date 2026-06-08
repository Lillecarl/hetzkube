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
    version = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = "2.21.2";
    };
  };
  config = lib.mkIf cfg.enable {
    importyaml.${moduleName} = {
      src = "https://raw.githubusercontent.com/hetznercloud/csi-driver/v${cfg.version}/deploy/kubernetes/hcloud-csi.yml";
    };
    kubernetes.objects.kube-system.VMServiceScrape = {
      hcloud-csi = {
        spec = {
          selector = {
            matchLabels = {
              app = "hcloud-csi";
            };
          };
          namespaceSelector = {
            matchNames = [ "kube-system" ];
          };
          endpoints = [
            {
              port = "9189";
              path = "/metrics";
              interval = "30s";
            }
          ];
        };
      };
    };
  };
}
