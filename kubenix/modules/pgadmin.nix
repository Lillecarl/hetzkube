{
  config,
  pkgs,
  pkgsArm,
  lib,
  ...
}:
let
  moduleName = "pgadmin";
  cfg = config.${moduleName};
in
{
  options.${moduleName} = {
    enable = lib.mkEnableOption moduleName;
    hostname = lib.mkOption {
      type = lib.types.str;
    };
    namespace = lib.mkOption {
      type = lib.types.str;
      default = moduleName;
    };
  };
  config = lib.mkIf cfg.enable {
    # Enable CNPG
    cnpg.enable = true;
    # Database configuration
    kubernetes.resources.cnpg-user =
      let
        user = "pgadmin";
      in
      {
        Secret."pg0-${user}" = {
          type = "kubernetes.io/basic-auth";
          metadata.labels."cnpg.io/reload" = "true";
          stringData = {
            username = user;
            password = "{{ lillepass }}";
          };
        };
        Cluster.pg0.spec.managed.roles.${user} = {
          login = true;
          passwordSecret.name = "pg0-${user}";
        };
        Database.${user}.spec = {
          name = user;
          owner = user;
          cluster.name = "pg0";
          databaseReclaimPolicy = "delete";
        };
      };

    # pgadmin namespace
    kubernetes.resources.none.Namespace.${cfg.namespace} = { };
    # pgadmin configuration
    kubernetes.resources.${cfg.namespace} = {
      Secret.secrets.stringData = {
        PGADMIN_DEFAULT_EMAIL = "admin@lillecarl.com";
        PGADMIN_DEFAULT_PASSWORD = "{{ lillepass }}";
      };
      ConfigMap.pgadmin4.data."config_local.py" = # python
        ''
          AUTHENTICATION_SOURCES = ['oauth2', 'internal']
          OAUTH2_CONFIG = [
              {
                  'OAUTH2_NAME': 'keycloak',
                  'OAUTH2_DISPLAY_NAME': 'Keycloak',
                  'OAUTH2_ICON': 'fa-openid',
                  'OAUTH2_CLIENT_ID': 'pgadmin',
                  'OAUTH2_CLIENT_SECRET': "", # we use PKCE/public but this must be set anyways
                  'OAUTH2_TOKEN_URL': 'https://${config.keycloak.hostname}/realms/master/protocol/openid-connect/token',
                  'OAUTH2_AUTHORIZATION_URL': 'https://${config.keycloak.hostname}/realms/master/protocol/openid-connect/auth',
                  'OAUTH2_API_BASE_URL': 'https://${config.keycloak.hostname}/realms/master/protocol/openid-connect',
                  'OAUTH2_USERINFO_ENDPOINT': 'https://${config.keycloak.hostname}/realms/master/protocol/openid-connect/userinfo',
                  'OAUTH2_SERVER_METADATA_URL': 'https://${config.keycloak.hostname}/realms/master/.well-known/openid-configuration',
                  'OAUTH2_SCOPE': 'openid email profile',
                  'OAUTH2_ICON': 'fa-key',
                  # Claims mapping
                  'OAUTH2_USERNAME_CLAIM': 'preferred_username',
                  'OAUTH2_EMAIL_CLAIM': 'email',
                  # Optional: Auto-create users that don't exist
                  'OAUTH2_AUTO_CREATE_USER': True,
                  # Optional: Additional parameters
                  'OAUTH2_ADDITIONAL_PARAMS': {
                      'access_type': 'offline'
                  },
                  'OAUTH2_SSL_CERT_VERIFICATION': True,
                  'OAUTH2_CHALLENGE_METHOD': 'S256',
                  'OAUTH2_RESPONSE_TYPE': 'code',
              }
          ]
        '';
      StatefulSet.${moduleName} = {
        spec = {
          replicas = 1;
          selector.matchLabels.app = moduleName;
          template = {
            metadata.labels.app = moduleName;
            metadata.annotations.configHash =
              lib.hashAttrs
                config.kubernetes.resources.${cfg.namespace}.ConfigMap.pgadmin4;
            spec = {
              securityContext.fsGroup = 5050; # pgadmin container pgadmin uid
              containers = lib.mkNamedList {
                ${moduleName} = {
                  image = "docker.io/dpage/pgadmin4:latest";
                  envFrom = [
                    { secretRef.name = "secrets"; }
                    # { secretRef.name = "tf-secrets"; }
                  ];
                  volumeMounts = lib.mkNamedList {
                    "data".mountPath = "/var/lib/pgadmin";
                    pgadmin4 = {
                      mountPath = "/pgadmin4/config_local.py";
                      subPath = "config_local.py";
                    };
                  };
                };
              };
              volumes = lib.mkNamedList {
                pgadmin4.configMap.name = "pgadmin4";
              };
            };
          };
          volumeClaimTemplates = [
            {
              metadata.name = "data";
              spec = {
                accessModes = [ "ReadWriteOnce" ];
                resources.requests.storage = "1Gi";
              };
            }
          ];
        };
      };
      Ingress.${moduleName} = {
        metadata.annotations = {
          "cert-manager.io/cluster-issuer" = "le-prod";
          "external-dns.alpha.kubernetes.io/ttl" = "60";
        };
        spec = {
          tls = [
            {
              hosts = [ cfg.hostname ];
              secretName = "cert";
            }
          ];
          rules = [
            {
              host = cfg.hostname;
              http = {
                paths = [
                  {
                    path = "/";
                    pathType = "Prefix";
                    backend = {
                      service = {
                        name = moduleName;
                        port = {
                          name = "http";
                        };
                      };
                    };
                  }
                ];
              };
            }
          ];
        };
      };
      Service.${moduleName} = {
        metadata.labels.app = moduleName;
        spec = {
          ports = [
            {
              protocol = "TCP";
              port = 8080;
              targetPort = 80;
              name = "http";
            }
          ];
          selector.app = moduleName;
          type = "ClusterIP";
        };
      };
    };
  };
}
