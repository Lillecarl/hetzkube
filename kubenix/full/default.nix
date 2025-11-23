{ config, lib, ... }:
{
  config = lib.mkIf (config.stage == "full") {
    capi.enable = true;
    cert-manager.bare = false;
    cert-manager.enable = true;
    chaoskube.chaoskube.enable = true;
    cheapam.enable = true;
    cilium.enable = true;
    cnpg.enable = true;
    coredns.enable = true;
    external-dns.enable = true;
    hcsi.enable = true;
    keycloak.enable = true;
    local-path-provisioner.enable = true;
    metallb.enable = true;
    metrics-server.enable = true;
    nix-csi.enable = true;
    pgadmin.enable = true;
  };
}
