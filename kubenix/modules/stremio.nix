# See https://github.com/keycloak/keycloak-quickstarts/blob/main/kubernetes/
{
  config,
  lib,
  ...
}:
let
  moduleName = "stremio";
  cfg = config.${moduleName};
in
{
  options.${moduleName} = {
    enable = lib.mkEnableOption moduleName;
    namespace = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = "stremio";
    };
    hostname = lib.mkOption {
      type = lib.types.str;
      description = "hostname for ${moduleName}";
    };
    version = lib.mkOption {
      type = lib.types.str;
      description = "${moduleName} version";
      default = "latest";
    };
  };
  config = lib.mkIf cfg.enable {
    kubernetes.resources.none.Namespace.${cfg.namespace} = { };
    kubernetes.resources.${cfg.namespace} = {
      Deployment.stremio-server = {
        spec = {
          replicas = 1;
          selector.matchLabels.app = "stremio-server";
          template = {
            metadata.labels.app = "stremio-server";
            spec = {
              containers = [
                {
                  name = "stremio-server";
                  image = "docker.io/stremio/server:${cfg.version}";
                  ports = [
                    {
                      containerPort = 11470;
                      protocol = "TCP";
                    }
                  ];
                  env = [
                    {
                      name = "NO_CORS";
                      value = "1";
                    }
                  ];
                }
              ];
            };
          };
        };
      };

      Service.stremio-server = {
        metadata.annotations = {
          # "ingress.cilium.io/auth-type" = "basic";
          # "ingress.cilium.io/auth-secret" = "stremio-basic-auth";
          # "ingress.cilium.io/auth-realm" = "Stremio Server";
        };
        spec = {
          selector.app = "stremio-server";
          ports = [
            {
              port = 11470;
              targetPort = 11470;
              protocol = "TCP";
            }
          ];
        };
      };

      Ingress.stremio-server = {
        metadata.annotations = {
          "cert-manager.io/cluster-issuer" = "le-prod";
        };
        spec = {
          ingressClassName = "cilium";
          rules = [
            {
              host = cfg.hostname;
              http.paths = [
                {
                  path = "/";
                  pathType = "Prefix";
                  backend.service = {
                    name = "stremio-server";
                    port.number = 11470;
                  };
                }
              ];
            }
          ];
          tls = [
            {
              hosts = [ cfg.hostname ];
              secretName = "stremio-tls";
            }
          ];
        };
      };

      Secret.stremio-basic-auth = {
        type = "Opaque";
        stringData.auth = "bGlsbGVjYXJsOiRhcHIxJHpVV0NocVhjJGVTTUF2cldrYjBCbWF3TjRZd1cyVS8KCg==";
      };
    };
  };
}
