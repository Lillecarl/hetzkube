{ config, lib, ... }:
{
  config = lib.mkIf (config.stage == "full") {
    cilium.enable = true;
    hccm.enable = true;
    cert-manager = {
      enable = true;
      bare = true;
    };
    coredns.enable = true;
    capi.enable = true;
    hcsi.enable = true;
    metallb.enable = true;
    ingress-nginx.enable = true;
    nix-csi.enable = true;
    external-dns.enable = true;
    chaoskube.chaoskube.enable = true;
    cheapam.enable = true;
  };
}
