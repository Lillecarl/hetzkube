{ config, lib, ... }:
{
  config = lib.mkIf (config.stage == "full") {
    capi.enable = true;
    cheapam.enable = true;
    cnpg.enable = true;
    coredns.enable = true;
    external-dns.enable = true;
    external-secrets.enable = true;
    fullstopslop.enable = true;
    hcsi.enable = true;
    headlamp.enable = false;
    keycloak.enable = true;
    kro.enable = false;
    local-path-provisioner.enable = true;
    metallb.enable = true;
    metrics-server.enable = true;
    nix-csi.enable = true;
    pgadmin.enable = true;
    sealed-secrets.enable = true;
    vertical-pod-autoscaler.enable = true;
  };
}
