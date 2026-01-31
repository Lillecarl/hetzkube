{ config, lib, ... }:
{
  imports = [
    ./alloy.nix
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
    ./hcsi.nix
    ./headlamp.nix
    ./keycloak.nix
    ./kro.nix
    ./kube-prometheus-stack.nix
    ./kyverno.nix
    ./local-path-provisioner.nix
    ./loki.nix
    ./metallb.nix
    ./metrics-server.nix
    ./pgadmin.nix
    ./sealed-secrets.nix
    ./stremio.nix
    ./vertical-pod-autoscaler.nix
  ];
  options.hlib = lib.mkOption {
    type = lib.types.anything;
    default = { };
  };
  config = {
    _module.args.hlib = config.hlib;
  };
}
