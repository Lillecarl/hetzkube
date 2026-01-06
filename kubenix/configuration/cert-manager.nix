{
  config,
  pkgs,
  lib,
  hlib,
  ...
}:
let
  email = "le@lillecarl.com";
in
{
  config = lib.mkIf (config.stage == "full") {
    cert-manager.enable = true;
    kubernetes.resources.cert-manager = {
      ExternalSecret.cloudflare = hlib.eso.mkToken "name:cloudflare-token";
    };
    kubernetes.resources.none.ClusterIssuer.le-staging.spec = {
      acme = {
        server = "https://acme-staging-v02.api.letsencrypt.org/directory";
        email = email;
        privateKeySecretRef.name = "le-staging-pk";
        solvers = lib.mkNumberedList {
          "0" = {
            dns01.cloudflare.apiTokenSecretRef = {
              name = "cloudflare";
              key = "token";
            };
          };
        };
      };
    };
    kubernetes.resources.none.ClusterIssuer.le-prod.spec = {
      acme = {
        server = "https://acme-v02.api.letsencrypt.org/directory";
        email = email;
        privateKeySecretRef.name = "le-prod-pk";
        solvers = lib.mkNumberedList {
          "0" = {
            dns01.cloudflare.apiTokenSecretRef = {
              name = "cloudflare";
              key = "token";
            };
          };
        };
      };
    };
  };
}
