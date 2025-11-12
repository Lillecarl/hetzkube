{
  config,
  lib,
  ...
}:
let
  moduleName = "cert-manager";
  cfg = config.${moduleName};
in
{
  options.${moduleName} = {
    enable = lib.mkEnableOption moduleName;
    url = lib.mkOption {
      type = lib.types.nonEmptyStr;
      default = "https://github.com/cert-manager/cert-manager/releases/download/v1.19.1/cert-manager.yaml";
    };
    bare = lib.mkOption {
      type = lib.types.bool;
    };
    email = lib.mkOption {
      type = lib.types.nonEmptyStr;
    };
  };
  config = lib.mkMerge [
    {
      kubernetes.apiMappings = {
        Certificate = "cert-manager.io/v1";
        CertificateRequest = "cert-manager.io/v1";
        Challenge = "acme.cert-manager.io/v1";
        ClusterIssuer = "cert-manager.io/v1";
        Issuer = "cert-manager.io/v1";
        Order = "acme.cert-manager.io/v1";
      };
      kubernetes.namespacedMappings = {
        Certificate = true;
        CertificateRequest = true;
        Challenge = true;
        ClusterIssuer = true;
        Issuer = true;
        Order = true;
      };
    }
    (lib.mkIf cfg.enable {
      importyaml.${moduleName} = {
        src = cfg.url;
      };
    })
    (lib.mkIf (cfg.enable && !cfg.bare) {
      kubernetes.resources.cert-manager.Secret.cloudflare.stringData.api-token = "{{ cftoken }}";
      kubernetes.resources.none.ClusterIssuer.le-staging.spec = {
        acme = {
          server = "https://acme-staging-v02.api.letsencrypt.org/directory";
          email = cfg.email;
          privateKeySecretRef.name = "le-staging-pk";
          solvers = {
            _numberedlist = true;
            "0" = {
              dns01.cloudflare.apiTokenSecretRef = {
                name = "cloudflare";
                key = "api-token";
              };
            };
          };
        };
      };
      kubernetes.resources.none.ClusterIssuer.le-prod.spec = {
        acme = {
          server = "https://acme-v02.api.letsencrypt.org/directory";
          email = cfg.email;
          privateKeySecretRef.name = "le-prod-pk";
          solvers = {
            _numberedlist = true;
            "0" = {
              dns01.cloudflare.apiTokenSecretRef = {
                name = "cloudflare";
                key = "api-token";
              };
            };
          };
        };
      };
    })
  ];
}
