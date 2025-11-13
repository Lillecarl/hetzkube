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
    ./haproxy.nix
    ./hccm.nix
    ./hcsi.nix
    ./ingress-nginx.nix
    ./metallb.nix
    ./metrics-server.nix
  ];
}
