{
  config,
  lib,
  hlib,
  ...
}:
{
  imports = [
    ./cert-manager.nix
    ./chaoskube.nix
    ./cilium.nix
    ./csi-driver-smb.nix
    ./external-secrets.nix
    ./kluctl.nix
    ./kube-prometheus-stack.nix
    ./nix-csi.nix
    ./vpa.nix
  ];
  options.stage = lib.mkOption {
    type = lib.types.enum [
      "capi"
      "full"
    ];
    default = "full";
  };
  options.copyDerivations = lib.mkOption {
    type = lib.types.listOf lib.types.package;
    default = [ ];
  };
  config = {
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

    capi.keyName = "lillecarl@lillecarl.com";
    keycloak.hostnames = [
      "auth.lillecarl.com" # Auth realm?
      "keycloak.lillecarl.com" # Keycloak admin
    ];
    pgadmin.hostname = "pgadmin.lillecarl.com";
    headlamp.hostname = "headlamp.lillecarl.com";

    kubernetes.transformers = [
      (
        resource:
        # Apply annotations to all LoadBalancers
        if resource.kind == "Service" && resource.spec.type or null == "LoadBalancer" then
          lib.recursiveUpdate resource {
            # IPv4 is scarce, share!
            metadata.annotations."metallb.io/allow-shared-ip" = "true";
            # Lowest TTL cloudflare allows
            metadata.annotations."external-dns.alpha.kubernetes.io/ttl" = "60";
          }
        # Make all services require dualstack
        else if resource.kind == "Service" then
          lib.recursiveUpdate resource {
            spec.ipFamilyPolicy = "RequireDualStack";
          }
        # Set lowest cloudflare TTL for ingress and gapi routes
        else if
          lib.elem resource.kind [
            "Ingress"
            "HTTPRoute"
          ]
        then
          lib.recursiveUpdate resource {
            metadata.annotations."external-dns.alpha.kubernetes.io/ttl" = "60";
          }
        else
          resource
      )
    ];

    coredns.replicas = 2;

    stremio = {
      enable = false;
      hostname = "stremio.lillecarl.com";
    };
    bitwarden.helmValues = {
      settings.bwSecretsManagerRefreshInterval = 180;
    };
    vertical-pod-autoscaler.helmValues = {
      admissionController.certManager.enabled = config.cert-manager.enable;
      updater.extraArgs = [
        "--min-replicas=1"
        "--eviction-tolerance=1.0"
      ];
      recommender.extraArgs = [
        "--pod-recommendation-min-memory-mb=0"
        "--pod-recommendation-min-cpu-millicores=0"
      ];
    };
    kubernetes.resources = lib.mkIf (config.stage == "full") {
      nix-csi.Service.nix-cache-lb.metadata.annotations."external-dns.alpha.kubernetes.io/hostname" =
        "nixcache.lillecarl.com";
      nix-csi.Service.nix-proxy.metadata.annotations."external-dns.alpha.kubernetes.io/hostname" =
        "nixbuild.lillecarl.com";
      kube-system.ConfigMap.cheapam-config.data.IPv4 = "10.133.0.0/16";
      nix-csi.StatefulSet = lib.mkIf config.nix-csi.cache.enable {
        nix-cache.spec.template.metadata.labels."cilium.io/ingress" = "true";
      };

      kube-system.ExternalSecret.hcloud = hlib.eso.mkToken "name:hcloud-token";
    };
  };
}
