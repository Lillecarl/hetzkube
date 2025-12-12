{ config, lib, ... }:
{
  config = lib.mkIf (config.stage == "full") {
    bitwarden.enable = true;
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
    headlamp.enable = false;
    keycloak.enable = true;
    kro.enable = false;
    # kube-prometheus-stack.enable = true;
    local-path-provisioner.enable = true;
    metallb.enable = false;
    metrics-server.enable = true;
    nix-csi.enable = true;
    pgadmin.enable = true;
    sealed-secrets.enable = true;
  };
}
