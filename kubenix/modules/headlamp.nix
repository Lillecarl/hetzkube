{
  config,
  pkgs,
  lib,
  ...
}:
let
  moduleName = "headlamp";
  cfg = config.${moduleName};
in
{
  options.${moduleName} = {
    enable = lib.mkEnableOption moduleName;
    namespace = lib.mkOption {
      type = lib.types.str;
      default = moduleName;
    };
    version = lib.mkOption {
      type = lib.types.str;
      default = "0.38.0";
    };
    hostname = lib.mkOption {
      type = lib.types.str;
    };
    helmValues = lib.mkOption {
      type = lib.types.anything;
      default = { };
    };
  };
  config = lib.mkIf cfg.enable {
    kubernetes.resources.none.Namespace.${cfg.namespace} = { };
    helm.releases.${moduleName} = {
      namespace = cfg.namespace;

      chart = "${
        builtins.fetchTree {
          type = "github";
          owner = "kubernetes-sigs";
          repo = "headlamp";
          ref = "v${cfg.version}";
        }
      }/charts/headlamp";

      values = lib.recursiveUpdate {
        image.tag = "v${cfg.version}";
        env = [
          {
            name = "OIDC_VALIDATOR_CLIENT_ID";
            value = "kubernetes";
          }
          {
            name = "HEADLAMP_CONFIG_OIDC_CLIENT_SECRET";
            valueFrom.secretKeyRef = {
              name = "headlamp-oidc-secret";
              key = "";
            };
          }
        ];
        ingress = {
          enabled = true;
          ingressClassName = "nginx";
          annotations = {
            "cert-manager.io/cluster-issuer" = "le-prod";
          };
          hosts = [
            {
              host = cfg.hostname;
              paths = [
                {
                  path = "/";
                  type = "Prefix";
                }
              ];
            }
          ];
          tls = [
            {
              secretName = "tls";
              hosts = [ cfg.hostname ];
            }
          ];
        };
        config = {
          oidc = {
            clientID = "headlamp";
            clientSecret = "x8C0dJr0SnyJnZfBFrnhg43qdkuxxDaT";
            issuerURL = "https://keycloak.lillecarl.com/realms/master";
            scopes = "openid,email,profile,offline_access";
          };
        };
      } cfg.helmValues;
    };
  };
}
