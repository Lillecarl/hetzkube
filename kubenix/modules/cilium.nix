{
  config,
  pkgs,
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
    helmValues = lib.mkOption {
      type = lib.types.anything;
      default = { };
    };
  };
  config = lib.mkMerge [
    (lib.mkIf cfg.enable {
      kubernetes.resources.none = {
        CiliumClusterwideNetworkPolicy.ssh.spec = {
          description = "Allow SSH + APIserver from anywhere and all intra-cluster traffic";
          nodeSelector.matchLabels = { }; # Applies to all nodes
          ingress = [
            {
              fromEntities = [ "cluster" ];
            }
            {
              fromCIDR = [
                "0.0.0.0/0"
                "::/0"
              ];
              toPorts = [
                {
                  ports = [
                    {
                      port = "22";
                      protocol = "TCP";
                    }
                    {
                      port = "6443";
                      protocol = "TCP";
                    }
                  ];
                }
              ];
            }
          ];
        };
      };
      kubernetes.resources.kube-system = {
        Secret.cilium-ca.metadata.annotations."kluctl.io/ignore-diff" = true;
        Secret.hubble-server-certs.metadata.annotations."kluctl.io/ignore-diff" = true;
        Secret.hubble-relay-client-certs.metadata.annotations."kluctl.io/ignore-diff" = true;
      };
      helm.releases.${moduleName} = {
        namespace = "kube-system";
        chart = "${
          builtins.fetchTree {
            type = "github";
            owner = "cilium";
            repo = "cilium";
            ref = "v1.18.3";
          }
        }/install/kubernetes/cilium";

        values = {
          # Only required for multi-cluster Cilium but it doesn't hurt.
          cluster.name = config.clusterName;
          # Enable IPv6 masquerading until we have a better solution
          enableIPv6Masquerade = false;
          # Disable LB IPAM, we use MetalLB for this
          enableLBIPAM = false;
          # Use cheapam to configure
          ipam.mode = "kubernetes";
          # Enable IPv6
          ipv6.enabled = true;
          ipam.operator = {
            clusterPoolIPv4MaskSize = 24;
            clusterPoolIPv4PodCIDRList = [ config.clusterPodCIDR4 ];
            clusterPoolIPv6MaskSize = 64;
            clusterPoolIPv6PodCIDRList = [ config.clusterPodCIDR6 ];
          };
          # Masquerade with BPF
          bpf.masquerade = true;
          # ServiceIP Cilium should use to talk to kube-apiserver. This is required
          # since Cilium is the CNI, uses hostNetwork and there's no cluster comms
          # before Cilium can talk to apiserver.
          k8sServiceHost = config.clusterHost;
          k8sServicePort = 6443;
          # Cilium replaces kube-proxy, so instead of iptables based service forwarding
          # Cilium uses it's own eBPF rules which scale better and can do more voodoo
          # at the expense of being harder to troubleshoot.
          kubeProxyReplacement = true;
          operator.replicas = 1;
          # Tunnel mode requires the least from the underlying network, as long as
          # hosts can communicate we're golden
          routingMode = "tunnel";
          # Can use GENEVE as well, useful if you have things in your network paths
          # which intercept vxlan that you don't wanna interact with (EVPN switches)
          tunnelProtocol = "vxlan";
        }
        // cfg.helmValues;
      };
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
