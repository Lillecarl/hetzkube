# See https://github.com/keycloak/keycloak-quickstarts/blob/main/kubernetes/
{
  config,
  lib,
  ...
}:
let
  moduleName = "keycloak";
  cfg = config.${moduleName};
in
{
  options.${moduleName} = {
    enable = lib.mkEnableOption moduleName;
    namespace = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = "keycloak";
    };
    hostname = lib.mkOption {
      description = "hostname for Keycloak";
      type = lib.types.str;
    };
  };
  config =
    let
      secretName = "keycloak-pg";
    in
    lib.mkIf cfg.enable {
      # Enable CNPG if it isn't enabled
      cnpg.enable = true;
      # Database configuration
      kubernetes.resources.cnpg-user = {
        Secret.pg0-keycloak = {
          type = "kubernetes.io/basic-auth";
          metadata.labels."cnpg.io/reload" = "true";
          stringData = {
            username = "keycloak";
            password = "{{ lillepass }}";
          };
        };
        Cluster.pg0.spec.managed.roles.keycloak = {
          ensure = "present";
          login = true;
          superuser = true;
          createdb = true;
          createrole = true;
          "inherit" = false;
          passwordSecret.name = "pg0-keycloak";
        };
        Database.keycloak.spec = {
          name = "keycloak";
          owner = "keycloak";
          cluster.name = "pg0";
          databaseReclaimPolicy = "delete";
        };
      };
      # Keycloak namespace
      kubernetes.resources.none.Namespace.${cfg.namespace} = { };
      # OIDC role configuration
      kubernetes.resources.none.ClusterRoleBinding.oidc-kubernetes-admin = {
        roleRef = {
          apiGroup = "rbac.authorization.k8s.io";
          kind = "ClusterRole";
          name = "cluster-admin";
        };
        subjects = [
          {
            kind = "Group";
            name = "kubernetes-admin";
          }
        ];
      };
      # Keycloak configuration
      kubernetes.resources.${cfg.namespace} = {
        Secret.${secretName}.stringData = {
          username = "keycloak";
          password = "{{ lillepass }}";
        };
        StatefulSet.keycloak = {
          metadata.labels.app = "keycloak";
          spec = {
            serviceName = "keycloak-discovery";
            replicas = 1;
            selector = {
              matchLabels = {
                app = "keycloak";
              };
            };
            template = {
              metadata = {
                labels = {
                  app = "keycloak";
                };
              };
              spec = {
                containers = [
                  {
                    name = "keycloak";
                    image = "quay.io/keycloak/keycloak:26.4";
                    imagePullPolicy = "Always"; # We want minor updates
                    args = [
                      "start"
                      "--proxy-headers"
                      "xforwarded"
                    ];
                    env = [
                      {
                        # Keycloak admin username
                        name = "KC_BOOTSTRAP_ADMIN_USERNAME";
                        valueFrom.secretKeyRef = {
                          name = secretName;
                          key = "username";
                        };
                      }
                      {
                        # Keycloak admin password
                        name = "KC_BOOTSTRAP_ADMIN_PASSWORD";
                        valueFrom.secretKeyRef = {
                          name = secretName;
                          key = "password";
                        };
                      }
                      {
                        name = "KC_PROXY_HEADERS";
                        value = "xforwarded";
                      }
                      {
                        name = "KC_HTTP_ENABLED";
                        value = "true";
                      }
                      {
                        name = "KC_HOSTNAME_STRICT";
                        value = "false";
                      }
                      {
                        name = "KC_HEALTH_ENABLED";
                        value = "true";
                      }
                      {
                        name = "KC_CACHE";
                        value = "ispn";
                      }
                      {
                        name = "POD_IP";
                        valueFrom = {
                          fieldRef = {
                            fieldPath = "status.podIP";
                          };
                        };
                      }
                      {
                        name = "KC_CACHE_EMBEDDED_NETWORK_BIND_ADDRESS";
                        value = "$(POD_IP)";
                      }
                      {
                        # Database type
                        name = "KC_DB";
                        value = "postgres";
                      }
                      {
                        # host
                        name = "KC_DB_URL_HOST";
                        value = "pb0-cluster.cnpg-user";
                      }
                      {
                        # dbname
                        name = "KC_DB_URL_DATABASE";
                        value = "keycloak";
                      }
                      {
                        # username
                        name = "KC_DB_USERNAME";
                        valueFrom.secretKeyRef = {
                          name = secretName;
                          key = "username";
                        };
                      }
                      {
                        # password
                        name = "KC_DB_PASSWORD";
                        valueFrom.secretKeyRef = {
                          name = secretName;
                          key = "password";
                        };
                      }
                    ];
                    ports = [
                      {
                        name = "http";
                        containerPort = 8080;
                      }
                      {
                        name = "jgroups";
                        containerPort = 7800;
                      }
                      {
                        name = "jgroups-fd";
                        containerPort = 57800;
                      }
                    ];
                    startupProbe = {
                      httpGet = {
                        path = "/health/started";
                        port = 9000;
                      };
                      periodSeconds = 1;
                      failureThreshold = 600;
                    };
                    readinessProbe = {
                      httpGet = {
                        path = "/health/ready";
                        port = 9000;
                      };
                      periodSeconds = 10;
                      failureThreshold = 3;
                    };
                    livenessProbe = {
                      httpGet = {
                        path = "/health/live";
                        port = 9000;
                      };
                      periodSeconds = 10;
                      failureThreshold = 3;
                    };
                    resources = {
                      # limits = {
                      #   cpu = "2000m";
                      #   memory = "2000Mi";
                      # };
                      # requests = {
                      #   cpu = "500m";
                      #   memory = "1700Mi";
                      # };
                    };
                  }
                ];
                topologySpreadConstraints = [
                  {
                    maxSkew = 1;
                    topologyKey = "kubernetes.io/hostname";
                    whenUnsatisfiable = "DoNotSchedule";
                    labelSelector.matchLabels.app = "keycloak";
                  }
                ];
              };
            };
          };
        };
        Ingress.keycloak = {
          metadata.annotations = {
            "cert-manager.io/cluster-issuer" = "le-prod";
            "external-dns.alpha.kubernetes.io/ttl" = "60";
          };
          spec = {
            tls = [
              {
                hosts = [ cfg.hostname ];
                secretName = "keycloak-cert";
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
                          name = "keycloak";
                          port = {
                            number = 8080;
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
        Service.keycloak = {
          metadata.labels.app = "keycloak";
          spec = {
            ports = [
              {
                protocol = "TCP";
                port = 8080;
                targetPort = "http";
                name = "http";
              }
            ];
            selector.app = "keycloak";
            type = "ClusterIP";
          };
        };
        Service.keycloak-discovery = {
          metadata.labels.app = "keycloak";
          spec = {
            selector.app = "keycloak";
            clusterIP = "None";
            type = "ClusterIP";
          };
        };
      };
    };
}
