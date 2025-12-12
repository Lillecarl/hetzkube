{ ... }:
{
  imports = [
    ./bitwarden.nix
    ./capi.nix
    ./cert-manager.nix
    ./chaoskube.nix
    ./cheapam.nix
    ./cilium.nix
    ./clusteroptions.nix
    ./cnpg.nix
    ./coredns.nix
    ./external-dns.nix
    ./gateway-api.nix
    ./hcsi.nix
    ./headlamp.nix
    ./keycloak.nix
    ./kro.nix
    ./kube-prometheus-stack.nix
    ./local-path-provisioner.nix
    ./metallb.nix
    ./metrics-server.nix
    ./pgadmin.nix
    ./sealed-secrets.nix
  ];
}
