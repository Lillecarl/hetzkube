{ ... }:
{
  imports = [
    ./capi.nix
    ./cert-manager.nix
    ./chaoskube.nix
    ./cheapam.nix
    ./cilium.nix
    ./clusteroptions.nix
    ./cnpg.nix
    ./coredns.nix
    ./external-dns.nix
    ./hcsi.nix
    ./headlamp.nix
    ./keycloak.nix
    ./local-path-provisioner.nix
    ./metallb.nix
    ./metrics-server.nix
    ./pgadmin.nix
    ./sealed-secrets.nix
  ];
}
