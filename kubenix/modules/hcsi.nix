{
  config,
  pkgs,
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
      default = "2.22.0";
    };
  };
  config = lib.mkIf cfg.enable {
    importyaml.${moduleName} = {
      src =
        "${
          pkgs.fetchFromGitHub {
            owner = "hetznercloud";
            repo = "csi-driver";
            rev = "v${cfg.version}";
            hash = "sha256-ouFq1pb60w5acJyzos21wjyFq8O5InxgmGmbzdF9E4A=";
          }
        }/deploy/kubernetes/hcloud-csi.yml";
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
