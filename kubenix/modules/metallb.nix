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
      # v0.16.0 controller needs pods/get in its namespace for owner references
      # Chart only creates this Role when speaker.enabled = true, so we add it here
      Role.metallb-pod-lister = {
        rules = [{
          apiGroups = [ "" ];
          resources = [ "pods" ];
          verbs = [ "list" "get" ];
        }];
      };
      RoleBinding.metallb-pod-lister = {
        roleRef = {
          apiGroup = "rbac.authorization.k8s.io";
          kind = "Role";
          name = "metallb-pod-lister";
        };
        subjects = [{
          kind = "ServiceAccount";
          name = "metallb-controller";
        }];
      };
    };
    helm.releases.${moduleName} = {
      namespace = "metallb-system";
      chart = "${
        builtins.fetchTree {
          type = "github";
          owner = "metallb";
          repo = "metallb";
          ref = "v0.16.0";
        }
      }/charts/metallb";

      values = lib.recursiveUpdate {
        speaker.enabled = lib.mkDefault false;
        frrk8s.enabled = lib.mkDefault false;
        controller.webhookMode = lib.mkDefault "disabled";
        controller.livenessProbe.enabled = lib.mkDefault false;
        controller.readinessProbe.enabled = lib.mkDefault false;
        crds.validationFailurePolicy = lib.mkDefault "Ignore";
      } cfg.helmValues;
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
