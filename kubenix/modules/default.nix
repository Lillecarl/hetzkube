{ config, lib, ... }:
{
  imports = [
    ./argocd.nix
    ./bitwarden.nix
    ./capi.nix
    ./cert-manager.nix
    ./chaoskube.nix
    ./cheapam.nix
    ./cilium.nix
    ./clusteroptions.nix
    ./cnpg.nix
    ./coredns.nix
    ./csi-driver-smb.nix
    ./external-dns.nix
    ./external-secrets.nix
    ./flux.nix
    ./gateway-api.nix
    ./grafana-operator.nix
    ./hcsi.nix
    ./headlamp.nix
    ./keycloak.nix
    ./kro.nix
    ./kube-proxy.nix
    ./kube-state-metrics.nix
    ./kubernetes-mixins.nix
    ./kyverno.nix
    ./local-path-provisioner.nix
    ./loki.nix
    ./metallb.nix
    ./metrics-server.nix
    ./node-exporter.nix
    ./oauth2-proxy.nix
    ./pgadmin.nix
    ./sealed-secrets.nix
    ./vertical-pod-autoscaler.nix
    ./victoriametrics.nix
  ];
  options.hlib = lib.mkOption {
    type = lib.types.anything;
    default = { };
  };
  config = {
    _module.args.hlib = config.hlib;
  };
}
