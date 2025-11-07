{
  config,
  pkgs,
  lib,
  ...
}:
let
  moduleName = "metallb";
  cfg = config.${moduleName};
in
{
  options.${moduleName} = {
    enable = lib.mkEnableOption moduleName;
    helmValues = lib.mkOption {
      type = lib.types.anything;
      default = { };
    };
  };
  config = lib.mkIf cfg.enable {
    kubernetes.resources.none.Namespace.metallb-system = { };
    kubernetes.resources.metallb-system = {
      L2Advertisement.default = { };
    };
    helm.releases.${moduleName} = {
      namespace = "metallb-system";
      chart = "${
        builtins.fetchTree {
          type = "github";
          owner = "metallb";
          repo = "metallb";
          ref = "v0.15.2";
        }
      }/charts/metallb";

      values = {
        speaker.enabled = lib.mkDefault false;
      }
      // cfg.helmValues;
    };
    kubernetes.apiMappings = {
      BFDProfile = "metallb.io/v1beta1";
      BGPAdvertisement = "metallb.io/v1beta1";
      BGPPeer = "metallb.io/v1beta2";
      Community = "metallb.io/v1beta1";
      IPAddressPool = "metallb.io/v1beta1";
      L2Advertisement = "metallb.io/v1beta1";
      ServiceBGPStatus = "metallb.io/v1beta1";
      ServiceL2Status = "metallb.io/v1beta1";
    };
    kubernetes.namespacedMappings = {
      BFDProfile = true;
      BGPAdvertisement = true;
      BGPPeer = true;
      Community = true;
      IPAddressPool = true;
      L2Advertisement = true;
      ServiceBGPStatus = true;
      ServiceL2Status = true;
    };
  };
}
