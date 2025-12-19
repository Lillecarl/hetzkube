{
  config,
  pkgs,
  lib,
  ...
}:
let
  email = "le@lillecarl.com";
in
{
  config = lib.mkIf (config.stage == "full") {
    cert-manager.enable = true;
    kubernetes.resources.cert-manager = {
      # Secret.cloudflare.stringData.token = "{{ cftoken }}";
      Secret.bw-auth-token.stringData.token = "{{ bwtoken }}";
      BitwardenSecret.cloudflare = {
        spec = {
          organizationId = "a5c85a84-042e-44b8-a07e-b16f00119301";
          secretName = "cloudflare";
          map = [
            {
              bwSecretId = "92277b8d-37e0-434f-b30f-b3b100adcc03";
              secretKeyName = "token";
            }
          ];
          authToken = {
            secretName = "bw-auth-token";
            secretKey = "token";
          };
        };
      };
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
