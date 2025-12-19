{
  config,
  lib,
  ...
}:
{
  imports = [
    ./kluctl.nix
    ./cilium.nix
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
      labels = {
        "chaos.alpha.kubernetes.io/disabled" = "";
      };
      args = {
        no-dry-run = "";
        interval = "15m";
        minimum-age = "6h";
        timezone = "Europe/Stockholm";
        # Don't kill primary databases, CNPG takes awhile to recover
        # Don't kill k8s control-plane components
        labels = "cnpg.io/instanceRole!=primary,tier!=control-plane";
        # Allow annotation to disable chaoskube targeting
        annotations = "!chaos.alpha.kubernetes.io/disabled";
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

    coredns.replicas = 2;

    nix-csi = {
      namespace = "nix-csi";
      internalServiceName = "hetzkube";
      cache.storageClassName = "hcloud-volumes";
      version = "develop";
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
      nix-csi.Service.nix-cache-lb.metadata.annotations."metallb.io/allow-shared-ip" = "true";
      nix-csi.Service.nix-cache-lb.metadata.annotations."lbipam.cilium.io/sharing-key" = "*";
      nix-csi.Service.nix-cache-lb.metadata.annotations."lbipam.cilium.io/sharing-cross-namespace" = "*";
      nix-csi.Service.nix-cache-lb.metadata.annotations."external-dns.alpha.kubernetes.io/ttl" = "60";
      nix-csi.Service.nix-cache-lb.metadata.annotations."external-dns.alpha.kubernetes.io/hostname" =
        "nixbuild.lillecarl.com";
      kube-system.ConfigMap.cheapam-config.data.IPv4 = "10.133.0.0/16";
      nix-csi.StatefulSet.nix-cache.spec.template.metadata.labels."cilium.io/ingress" = "true";

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
