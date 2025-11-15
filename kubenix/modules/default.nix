{ lib, ... }:
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
    ./hccm.nix
    ./hcsi.nix
    ./metallb.nix
    ./metrics-server.nix
  ];
}
