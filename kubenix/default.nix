{
  pkgs,
  easykubenix,
  nix-csi,
  args,
}:
let
  inherit (pkgs) lib;
  stage =
    if lib.hasAttr "stage" args then
      args.stage
    else
      throw ''
        You must specify a stage using the following arguments:
        --argstr stage $stage
      '';

  stages = rec {
    # Only on some ephemeral init cluster
    capi = {
      capi.enable = true;
    };
    # This is run by CAPI as a postKubeadmCommand on the first node.
    # Don't run this unless you know what you're doing++
    init = {
      cilium.enable = true;
      hccm.enable = true;
      cert-manager = {
        enable = true;
        bare = true;
      };
      coredns.enable = true;
    };
    # Don't run full stage until you've migrated CAPI into the cluster
    full = lib.recursiveUpdate init {
      capi.enable = true;
      cert-manager.bare = false;
      hcsi.enable = true;
      metallb.enable = true;
      nginx.enable = true;
      nix-csi.enable = true;
      external-dns.enable = true;
      # TODO: This doesn't belong here
      kubernetes.resources = {
        nix-csi.Service.nix-cache-lb.metadata.annotations."metallb.io/allow-shared-ip" = "true";
        nix-csi.Service.nix-cache-lb.metadata.annotations."external-dns.alpha.kubernetes.io/ttl" = "60";
        nix-csi.Service.nix-cache-lb.metadata.annotations."external-dns.alpha.kubernetes.io/hostname" =
          "nixbuild.lillecarl.com";
      };
    };
  };
  stageMod = stages.${stage};
in
import easykubenix {
  inherit pkgs;
  modules = [
    ./capi.nix
    ./cert-manager.nix
    ./cilium.nix
    ./clusteroptions.nix
    ./coredns.nix
    ./external-dns.nix
    ./hccm.nix
    ./hcsi.nix
    ./metallb.nix
    ./nginx.nix
    "${nix-csi}/kubenix"
    stageMod # We only use stages to enable or disable things
    {
      config = {
        kluctl = {
          discriminator = stage; # And set discriminator
          deployment.vars = [ { file = "secrets/all.yaml"; } ];
          files."secrets/all.yaml" = builtins.readFile ../secrets/all.yaml;
        };
        clusterName = "hetzkube";
        clusterHost = "kubernetes.lillecarl.com";
        clusterDomain = "cluster.local";
        clusterDNS = [
          "10.134.0.10"
          "fdce:9c4d:dcba::10"
        ];
        clusterPodCIDR4 = "10.133.0.0/16"; # 65536
        clusterPodCIDR6 = "fdce:9c4d:abcd::/48"; # Very big
        clusterServiceCIDR4 = "10.134.0.0/16"; # 65536
        clusterServiceCIDR6 = "fdce:9c4d:dcba::/112"; # 65536

        # If you don't set an SSH key Hetzner will kindly mail you invalid
        # credentials every time a server is created. Upload a key and set name
        capi.keyName = "lillecarl@lillecarl.com";
        cert-manager.email = "le@lillecarl.com";

        nix-csi = {
          namespace = "nix-csi";
          cache.storageClassName = "hcloud-volumes";
        };
        hccm = {
          # Templated SOPS with kluctl
          apiToken = "{{ hctoken }}";
          values = {
            # Only use HCCM to assign providerID
            env.HCLOUD_LOAD_BALANCERS_ENABLED.value = "false";
            env.HCLOUD_NETWORK_ROUTES_ENABLED.value = "false";
            env.HCLOUD_NETWORK_DISABLE_ATTACHED_CHECK.value = "true";
            # We must IPv6!!
            env.HCLOUD_INSTANCES_ADDRESS_FAMILY.value = "dualstack";
            # Idk if this is needed, it's followed me for awhile
            additionalTolerations = [
              {
                key = "node.cilium.io/agent-not-ready";
                operator = "Exists";
              }
            ];
          };
        };
        hcsi.apiToken = "{{ hctoken }}";
        nginx = {
          values = {
            controller = {
              # We don't HA here.
              replicaCount = 1;
              # Get certificate for admissionwebhook from cert-manager instead
              # of dumb unreliable Helm hook.
              admissionWebhooks.certManager.enabled = true;
              config = {
                # Set forwarded headers
                enable-real-ip = true;
                # Allow annotating config per ingress. YOLO
                allow-snippet-annotations = true;
              };
              service.annotations."metallb.io/allow-shared-ip" = "true";
            };
          };
        };
        kubernetes.resources.kube-public.ConfigMap.initialized = { };
      };
    }
  ];
}
