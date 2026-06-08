{
  config,
  pkgs,
  lib,
  ...
}:
{
  imports = [
    ./dns.nix
    ./keycloak
  ];
  config = {
    terraform.backend.kubernetes = {
      namespace = "kube-system";
      config_path = "/home/lillecarl/.kube/config";
      secret_suffix = "tf0";
    };
    provider.keycloak = {
      client_id = "admin-cli";
      url = "https://keycloak.lillecarl.com";
    };
    data.kubernetes_secret_v1.scaleway = {
      metadata = {
        name = "scaleway-dns-key";
        namespace = "kube-system";
      };
    };
    provider.scaleway = {
      access_key = lib.tfRef "data.kubernetes_secret_v1.scaleway.data.username";
      secret_key = lib.tfRef "data.kubernetes_secret_v1.scaleway.data.password";
    };

    variable.KUBECONFIG.type = "string";
    provider.kubernetes = {
      config_path = lib.tfRef "var.KUBECONFIG";
    };
  };
}
