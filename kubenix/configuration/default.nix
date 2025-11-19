{
  config,
  lib,
  ...
}:
{
  imports = [
    ./kluctl.nix
  ];
  options.stage = lib.mkOption {
    type = lib.types.enum [
      "capi"
      "full"
    ];
    default = "full";
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
    chaoskube.chaoskube = {
      args = {
        no-dry-run = "";
        interval = "15m";
        minimum-age = "6h";
        timezone = "Europe/Stockholm";
      };
    };

    # If you don't set an SSH key Hetzner will kindly mail you invalid
    # credentials every time a server is created. Upload a key and set name
    capi.keyName = "lillecarl@lillecarl.com";
    cert-manager.email = "le@lillecarl.com";
    # Must match with OIDC
    keycloak.hostname = "keycloak.lillecarl.com";
    pgadmin.hostname = "pgadmin.lillecarl.com";
    headlamp.hostname = "headlamp.lillecarl.com";

    nix-csi = {
      namespace = "nix-csi";
      internalServiceName = "hetzkube";
      cache.storageClassName = "hcloud-volumes";
    };
    hcsi.apiToken = "{{ hctoken }}";
    kubernetes.resources = lib.mkIf (config.stage == "full") {
      nix-csi.Service.nix-cache-lb.metadata.annotations."metallb.io/allow-shared-ip" = "true";
      nix-csi.Service.nix-cache-lb.metadata.annotations."external-dns.alpha.kubernetes.io/ttl" = "60";
      nix-csi.Service.nix-cache-lb.metadata.annotations."external-dns.alpha.kubernetes.io/hostname" =
        "nixbuild.lillecarl.com";
      kube-system.ConfigMap.cheapam-config.data.IPv4 = "10.133.0.0/16";
      nix-csi.StatefulSet.nix-cache.spec.template.metadata.labels."cilium.io/ingress" = "true";
    };
  };
}
