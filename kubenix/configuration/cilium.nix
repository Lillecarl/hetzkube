{
  config,
  pkgs,
  lib,
  ...
}:
{
  config = lib.mkIf (config.stage == "full") {
    cilium = {
      enable = true;
      helmValues = {
        # Probably don't change this, we apply catch-all rules instead.
        # Cilium developers say it can cause bootstrapping issues to set
        # this to always.
        policyEnforcementMode = "default";
        # Hubble
        hubble.relay.enabled = true;
        hubble.ui.enabled = true;
        # hubble.tls.auto.method = "certmanager";
        # hubble.tls.auto.certManagerIssuerRef = ""
        # Only required for multi-cluster Cilium but it doesn't hurt.
        cluster.name = config.clusterName;
        # Enable IPv6 masquerading until we have a better solution
        enableIPv6Masquerade = false;
        # Use LB IPAM, managed by cheapam
        enableLBIPAM = true;
        # Use cheapam to configure
        ipam.mode = "kubernetes";
        # Enable IPv6
        ipv6.enabled = true;
        # Masquerade with BPF
        bpf.masquerade = true;
        # Enable PMTUD in case we send traffic somewhere with a small MTU
        pmtuDiscovery.enabled = true;
        # Use Cilium as firewall for the entire nodes
        hostFirewall.enabled = true;
        # Select nodes by label
        nodeSelectorLabels = true;
        # Roll out when config changes
        rollOutCiliumPods = true;
        envoy.rollOutPods = true;
        hubble.relay.rollOutPods = true;
        hubble.ui.rollOutPods = true;
        operator.rollOutPods = true;
        # ServiceIP Cilium should use to talk to kube-apiserver. This is required
        # since Cilium is the CNI, uses hostNetwork and there's no cluster comms
        # before Cilium can talk to apiserver.
        k8sServiceHost = config.clusterHost;
        k8sServicePort = 6443;
        # Cilium replaces kube-proxy, so instead of iptables based service forwarding
        # Cilium uses it's own eBPF rules which scale better and can do more voodoo
        # at the expense of being harder to troubleshoot.
        kubeProxyReplacement = true;
        # Always tunnel
        autoDirectNodeRoutes = false;
        # Efficient on-node forwarding
        enableLocalRedirectPolicy = true;
        # RIP ingress-nginx
        ingressController = {
          enabled = true;
          default = true;
          # Only one LB service since we don't have unlimited IP port combos
          loadbalancerMode = "shared";
          # Allow sharing IP with other LB services
          service.annotations."lbipam.cilium.io/sharing-key" = "*";
          service.annotations."lbipam.cilium.io/sharing-cross-namespace" = "*";
          # Policy stuff
          service.labels.ingress = "all";
        };
        # Enable gateway API
        gatewayAPI = {
          enabled = true;
        };
        # Cilium is quite important
        operator.replicas = 2;
        # Tunnel mode requires the least from the underlying network, as long as
        # hosts can communicate we're golden
        routingMode = "tunnel";
        # Can use GENEVE as well, useful if you have things in your network paths
        # which intercept vxlan that you don't wanna interact with (EVPN switches)
        tunnelProtocol = "geneve";
      };
    };

    # Cilium network policies
    kubernetes.resources.none.CiliumClusterwideNetworkPolicy = {
      # nodeSelector and endpointSelector target different "something"
      # nodeSelector only apply to "node endpoints"
      # This is a "catch-all" policy
      node-default = {
        spec = {
          nodeSelector = { };
          ingress = [
            # Allow SSH and kube-apiserver from anywhere
            {
              fromEntities = [ "all" ];
              toPorts = [
                {
                  ports = [
                    # ssh
                    {
                      port = "22";
                      protocol = "TCP";
                    }
                    # etcd (since node isn't part of cluster when joining)
                    {
                      port = "2379";
                      protocol = "TCP";
                    }
                    {
                      port = "2380";
                      protocol = "TCP";
                    }
                    # apiserver
                    {
                      port = "6443";
                      protocol = "TCP";
                    }
                  ];
                }
              ];
            }
            # Allow all traffic from cluster
            { fromEntities = [ "cluster" ]; }
            # Allow ICMP requests from anywhere
            {
              fromEntities = [ "all" ];
              icmps = [
                {
                  fields = [
                    {
                      type = "EchoRequest";
                      family = "IPv4";
                    }
                    {
                      type = "EchoRequest";
                      family = "IPv6";
                    }
                  ];
                }
              ];
            }
          ];
          # Allow outbound traffic
          egress = [ { toEntities = [ "all" ]; } ];
        };
      };
      # Allow Cilium ingress
      ep-ingress-reserved = {
        spec = {
          endpointSelector.matchLabels."reserved:ingress" = "";
          ingress = [ { fromEntities = [ "all" ]; } ];
        };
      };
      # Allow "direct" connections directly to pods with this label
      ep-ingress-label = {
        spec = {
          endpointSelector.matchLabels."cilium.io/ingress" = "true";
          ingress = [ { fromEntities = [ "all" ]; } ];
        };
      };
      # endpointSelector selects in-cluster endpoints (ish)
      # This is a "catch-all" policy
      ep-default = {
        spec = {
          endpointSelector = { };
          ingress = [
            # Allow traffic from cluster or ingress
            {
              fromEntities = [
                "cluster"
                "ingress"
              ];
            }
            # Allow ICMP EchoRequest from anywhere
            {
              fromEntities = [ "all" ];
              icmps = [
                {
                  fields = [
                    {
                      type = "EchoRequest";
                      family = "IPv4";
                    }
                    {
                      type = "EchoRequest";
                      family = "IPv6";
                    }
                  ];
                }
              ];
            }
          ];
          # Allow all outbound traffic
          egress = [ { toEntities = [ "all" ]; } ];
        };
      };
    };
  };
}
