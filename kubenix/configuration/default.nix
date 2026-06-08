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
    ./cnpg-primaryswap.nix
    ./etcd-defrag.nix
    ./csi-driver-smb.nix
    ./external-dns.nix
    ./external-secrets.nix
    ./flux.nix
    ./grafana.nix
    ./kluctl.nix
    ./kyverno.nix
    ./ncps.nix
    ./nix-csi.nix
    ./otel-k8s.nix
    ./victoriametrics.nix
    ./vpa.nix
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

    capi.keyName = "lillecarl@lillecarl.com";
    keycloak.hostnames = [
      "auth.lillecarl.com" # Auth realm?
      "keycloak.lillecarl.com" # Keycloak admin
    ];
    pgadmin.hostname = "pgadmin.lillecarl.com";
    headlamp = {
      hostname = "headlamp.lillecarl.com";
      version = "0.40.0";
    };

    metrics-server.helmValues.replicas = 2;

    kubernetes.transformers = [
      # make all Service dualstack
      (
        resource:
        if resource.kind == "Service" then
          lib.recursiveUpdate resource {
            spec.ipFamilyPolicy = "RequireDualStack";
          }
        else
          resource
      )
      # apply DNS TTL to all Ingress and HTTPRoute
      (
        resource:
        if
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
      # DNS TTL and IP sharing for LoadBalancer Service
      (
        resource:
        if resource.kind == "Service" && resource.spec.type or null == "LoadBalancer" then
          lib.recursiveUpdate resource {
            # IPv4 is scarce, share!
            metadata.annotations."metallb.io/allow-shared-ip" = "true";
            # Lowest TTL cloudflare allows
            metadata.annotations."external-dns.alpha.kubernetes.io/ttl" = "60";
          }
        else
          resource
      )
      # Drop CPU limits, CPU limits are mostly dumb. Especially if VPA sets them to 0m
      (
        object:
        if
          lib.elem (object.kind or "") [
            "Deployment"
            "StatefulSet"
            "DaemonSet "
          ]
        then
          lib.mapAttrsRecursiveCond (as: !(as ? "cpu")) (
            path: value:
            if (lib.last path) == "limits" && lib.isAttrs value && value ? "cpu" then
              # value // { cpu = null; }
              lib.removeAttrs value [ "cpu" ]
            else
              value
          ) object
        else
          object
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

    # FluxCD, TODO move this to where we deploy Flux pls
    kubernetes.apiMappings = {
      HelmRelease = "helm.toolkit.fluxcd.io/v2";
      Kustomization = "kustomize.toolkit.fluxcd.io/v1";
      Alert = "notification.toolkit.fluxcd.io/v1beta3";
      Provider = "notification.toolkit.fluxcd.io/v1beta3";
      Receiver = "notification.toolkit.fluxcd.io/v1";
      Bucket = "source.toolkit.fluxcd.io/v1";
      ExternalArtifact = "source.toolkit.fluxcd.io/v1";
      GitRepository = "source.toolkit.fluxcd.io/v1";
      HelmChart = "source.toolkit.fluxcd.io/v1";
      HelmRepository = "source.toolkit.fluxcd.io/v1";
      OCIRepositoryk = "source.toolkit.fluxcd.io/v1";
    };
    kubernetes.namespacedMappings = {
      HelmRelease = true;
      Kustomization = true;
      Alert = true;
      Provider = true;
      Receiver = true;
      Bucket = true;
      ExternalArtifact = true;
      GitRepository = true;
      HelmChart = true;
      HelmRepository = true;
      OCIRepositoryk = true;
    };

    kubernetes.resources = lib.mkIf (config.stage == "full") {
      nixkube = lib.mkIf config.nixkube.enable {
        Service.pynixd-lb.metadata.annotations."external-dns.alpha.kubernetes.io/hostname" =
          "nixcache.lillecarl.com";
        StatefulSet = lib.mkIf config.nixkube.pynixd.enable {
          pynixd.spec.template.metadata.labels."cilium.io/ingress" = "true";
        };
      };
      kube-system.ConfigMap.cheapam-config.data.IPv4 = "10.133.0.0/16";

      kube-system.ExternalSecret.hcloud = hlib.eso.mkToken "name:hcloud-token";

      # Don't allow VPA to scale limits below what's actually usable
      none.LimitRange = {
        global-limit-floor = {
          spec.limits = [
            {
              type = "Container";
              min = {
                cpu = "250m";
                memory = "256Mi";
              };
            }
          ];
        };
      };

    };
  };
}
