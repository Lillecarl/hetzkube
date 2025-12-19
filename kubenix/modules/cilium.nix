{
  config,
  lib,
  ...
}:
let
  moduleName = "cilium";
  cfg = config.${moduleName};
in
{
  options.${moduleName} = {
    enable = lib.mkEnableOption moduleName;
    # You'll have to re-roll Cilium pods manually when changing this.
    policyAuditMode = lib.mkEnableOption "policy-audit-mode";
    version = lib.mkOption {
      type = lib.types.str;
      default = "1.18.4";
    };
    gatewayAPI = (lib.mkEnableOption "gateway api") // {
      default = true;
    };
    helmValues = lib.mkOption {
      type = lib.types.anything;
      default = { };
    };
  };
  config =
    let
      src = builtins.fetchTree {
        type = "github";
        owner = "cilium";
        repo = "cilium";
        ref = "v${cfg.version}";
      };
    in
    lib.mkMerge [
      (lib.mkIf (cfg.enable && cfg.gatewayAPI) {
        # Configure GatewayAPI version
        gateway-api.enable = true;
        gateway-api.version =
          lib.mkDefault
            {
              "1.16" = "1.1.0";
              "1.17" = "1.2.0";
              "1.18" = "1.2.0";
              "1.19" = "1.3.0";
            }
            .${lib.versions.majorMinor cfg.version};
      })
      (lib.mkIf cfg.enable {
        # Disables enforcing policies
        kubernetes.resources.kube-system.ConfigMap.cilium-config.data.policy-audit-mode =
          lib.boolToString cfg.policyAuditMode;

        kubernetes.resources.kube-system = {
          Secret.cilium-ca.metadata.annotations."kluctl.io/ignore-diff" = true;
          Secret.hubble-server-certs.metadata.annotations."kluctl.io/ignore-diff" = true;
          Secret.hubble-relay-client-certs.metadata.annotations."kluctl.io/ignore-diff" = true;
        };
        helm.releases.${moduleName} = {
          namespace = "kube-system";
          chart = "${src}/install/kubernetes/cilium";

          values = lib.recursiveUpdate {
          } cfg.helmValues;
        };
        # Install Cilium CRDs with easykubenix, required so we can install network policies before
        # cilium-operator has installed them itself.
        importyaml = lib.pipe (builtins.readDir "${src}/pkg/k8s/apis/cilium.io/client/crds/v2") [
          (lib.mapAttrs' (
            filename: type: {
              name = filename;
              value.src = "${src}/pkg/k8s/apis/cilium.io/client/crds/v2/${filename}";
            }
          ))
        ];
      })
      {
        kubernetes.apiMappings = {
          CiliumCIDRGroup = "cilium.io/v2";
          CiliumClusterwideNetworkPolicy = "cilium.io/v2";
          CiliumEndpoint = "cilium.io/v2";
          CiliumIdentity = "cilium.io/v2";
          CiliumL2AnnouncementPolicy = "cilium.io/v2alpha1";
          CiliumLoadBalancerIPPool = "cilium.io/v2";
          CiliumNetworkPolicy = "cilium.io/v2";
          CiliumNode = "cilium.io/v2";
          CiliumNodeConfig = "cilium.io/v2";
          CiliumPodIPPool = "cilium.io/v2alpha1";
        };
        kubernetes.namespacedMappings = {
          CiliumCIDRGroup = false;
          CiliumClusterwideNetworkPolicy = false;
          CiliumEndpoint = true;
          CiliumIdentity = false;
          CiliumL2AnnouncementPolicy = false;
          CiliumLoadBalancerIPPool = false;
          CiliumNetworkPolicy = true;
          CiliumNode = false;
          CiliumNodeConfig = true;
          CiliumPodIPPool = false;
        };
      }
    ];
}
