{
  config,
  lib,
  ...
}:
let
  moduleName = "oauth2-proxy";
  cfg = config.${moduleName};

  instanceModule =
    { name, ... }:
    {
      options = {
        enable = lib.mkEnableOption "oauth2-proxy instance ${name}";
        namespace = lib.mkOption {
          type = lib.types.nonEmptyStr;
          description = "Namespace to deploy this instance's Deployment/Service/ExternalSecret into.";
        };
        hostname = lib.mkOption {
          type = lib.types.nonEmptyStr;
          description = "Public hostname this instance is exposed on (used for the OIDC redirect URL).";
        };
        upstream = lib.mkOption {
          type = lib.types.nonEmptyStr;
          description = ''In-cluster upstream this instance proxies authenticated requests to, e.g. "http://vmalert-metrics:8080".'';
        };
        clientId = lib.mkOption {
          type = lib.types.nonEmptyStr;
          description = "Keycloak OIDC client ID (see tf/keycloak/default.nix).";
        };
        scalewaySecret = lib.mkOption {
          type = lib.types.nonEmptyStr;
          description = ''
            Scaleway secret name prefix (fetched via ESO). Two secrets must
            exist: "<prefix>-client-secret" (the Keycloak client's secret)
            and "<prefix>-cookie-secret" (32 random bytes, e.g. `openssl
            rand -base64 32`, for oauth2-proxy's own session cookie
            encryption).
          '';
        };
        emailDomains = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ "*" ];
          description = "oauth2-proxy's own allowlist, on top of whoever Keycloak already let log in. \"*\" defers entirely to Keycloak.";
        };
        image = lib.mkOption {
          type = lib.types.nonEmptyStr;
          default = "quay.io/oauth2-proxy/oauth2-proxy:v7.9.0";
        };
        resources = lib.mkOption {
          type = lib.types.anything;
          default = {
            requests = {
              cpu = "10m";
              memory = "32Mi";
            };
          };
        };
      };
    };
in
{
  options.${moduleName} = {
    instances = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule instanceModule);
      default = { };
      description = ''
        Named oauth2-proxy instances, each fronting one upstream with
        Keycloak OIDC auth. One instance per exposed hostname -- oauth2-proxy
        can't discriminate multiple upstreams by Host on its own, so
        multiple public hostnames behind one auth domain each need their own
        instance (they can still share one Keycloak client/secret pair).
      '';
    };
  };

  config.kubernetes.resources = lib.mkMerge (
    lib.mapAttrsToList (
      name: icfg:
      lib.mkIf icfg.enable {
        ${icfg.namespace} = {
          ExternalSecret."oauth2-proxy-${name}" = {
            spec = {
              refreshInterval = "30m0s";
              secretStoreRef = {
                kind = "ClusterSecretStore";
                name = "scaleway";
              };
              target.template.type = "Opaque";
              data = [
                {
                  secretKey = "client-secret";
                  remoteRef.key = "${icfg.scalewaySecret}-client-secret";
                }
                {
                  secretKey = "cookie-secret";
                  remoteRef.key = "${icfg.scalewaySecret}-cookie-secret";
                }
              ];
            };
          };
          Deployment."oauth2-proxy-${name}" = {
            metadata.labels."app.kubernetes.io/name" = "oauth2-proxy-${name}";
            spec = {
              replicas = 1;
              selector.matchLabels."app.kubernetes.io/name" = "oauth2-proxy-${name}";
              template = {
                metadata.labels."app.kubernetes.io/name" = "oauth2-proxy-${name}";
                spec.containers = lib.mkNamedList {
                  oauth2-proxy = {
                    image = icfg.image;
                    ports = lib.mkNamedList {
                      http.containerPort = 4180;
                    };
                    env = lib.mkNamedList {
                      OAUTH2_PROXY_PROVIDER.value = "oidc";
                      OAUTH2_PROXY_OIDC_ISSUER_URL.value = "https://${lib.head config.keycloak.hostnames}/realms/auth";
                      OAUTH2_PROXY_CLIENT_ID.value = icfg.clientId;
                      OAUTH2_PROXY_CLIENT_SECRET.valueFrom.secretKeyRef = {
                        name = "oauth2-proxy-${name}";
                        key = "client-secret";
                      };
                      OAUTH2_PROXY_COOKIE_SECRET.valueFrom.secretKeyRef = {
                        name = "oauth2-proxy-${name}";
                        key = "cookie-secret";
                      };
                      OAUTH2_PROXY_REDIRECT_URL.value = "https://${icfg.hostname}/oauth2/callback";
                      OAUTH2_PROXY_UPSTREAMS.value = icfg.upstream;
                      OAUTH2_PROXY_EMAIL_DOMAINS.value = lib.concatStringsSep "," icfg.emailDomains;
                      OAUTH2_PROXY_HTTP_ADDRESS.value = "0.0.0.0:4180";
                      OAUTH2_PROXY_COOKIE_SECURE.value = "true";
                      OAUTH2_PROXY_SKIP_PROVIDER_BUTTON.value = "true";
                      OAUTH2_PROXY_REVERSE_PROXY.value = "true";
                    };
                    inherit (icfg) resources;
                  };
                };
              };
            };
          };
          Service."oauth2-proxy-${name}" = {
            metadata.labels."app.kubernetes.io/name" = "oauth2-proxy-${name}";
            spec = {
              selector."app.kubernetes.io/name" = "oauth2-proxy-${name}";
              ports = [
                {
                  name = "http";
                  port = 4180;
                  targetPort = "http";
                  protocol = "TCP";
                }
              ];
            };
          };
        };
      }
    ) cfg.instances
  );
}
