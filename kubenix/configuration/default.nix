{
  config,
  lib,
  ...
}:
{
  imports = [
    ./cert-manager.nix
    ./chaoskube.nix
    ./cilium.nix
    ./external-secrets.nix
    ./kluctl.nix
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
    default = [];
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
    # Must match with OIDC
    keycloak.hostname = "keycloak.lillecarl.com";
    pgadmin.hostname = "pgadmin.lillecarl.com";
    headlamp.hostname = "headlamp.lillecarl.com";

    coredns.replicas = 2;

    nix-csi = {
      namespace = "nix-csi";
      internalServiceName = "hetzkube";
      cache.enable = true;
      cache.storageClassName = "hcloud-volumes";
      # version = "develop";
    };
    bitwarden.helmValues = {
      settings.bwSecretsManagerRefreshInterval = 180;
    };
    vertical-pod-autoscaler.helmValues = {
      admissionController.certManager.enabled = config.cert-manager.enable;
      recommender.extraArgs = [
        "--pod-recommendation-min-memory-mb=0"
        "--pod-recommendation-min-cpu-millicores=0"
      ];
    };
    kubernetes.resources = lib.mkIf (config.stage == "full") {
      nix-csi.Service.nix-cache-lb.metadata.annotations."lbipam.cilium.io/sharing-key" = "*";
      nix-csi.Service.nix-cache-lb.metadata.annotations."lbipam.cilium.io/sharing-cross-namespace" = "*";
      nix-csi.Service.nix-cache-lb.metadata.annotations."external-dns.alpha.kubernetes.io/ttl" = "60";
      nix-csi.Service.nix-cache-lb.metadata.annotations."external-dns.alpha.kubernetes.io/hostname" =
        "nixbuild.lillecarl.com";
      kube-system.ConfigMap.cheapam-config.data.IPv4 = "10.133.0.0/16";
      nix-csi.StatefulSet = lib.mkIf config.nix-csi.cache.enable {
        nix-cache.spec.template.metadata.labels."cilium.io/ingress" = "true";
      };

      kube-system.Secret.bw-auth-token.stringData.token = "{{ bwtoken }}";
      kube-system.BitwardenSecret.hcloud = {
        spec = {
          organizationId = "a5c85a84-042e-44b8-a07e-b16f00119301";
          secretName = "hcloud";
          map = [
            {
              bwSecretId = "4a2e1d5f-f44a-4034-afe1-b3b100adf118";
              secretKeyName = "token";
            }
          ];
          authToken = {
            secretName = "bw-auth-token";
            secretKey = "token";
          };
        };
      };
    };
  };
}
