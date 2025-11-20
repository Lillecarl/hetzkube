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
      type = lib.types.str;
      description = "hostname for ${moduleName}";
    };
    version = lib.mkOption {
      type = lib.types.str;
      description = "${moduleName} version";
      default = "26.4";
    };
  };
  config =
    let
      secretName = "${moduleName}-pg";
    in
    lib.mkIf cfg.enable {
      # Enable CNPG
      cnpg.enable = true;
      # Database configuration
      kubernetes.resources.cnpg-user = {
        Secret."pg0-${moduleName}" = {
          type = "kubernetes.io/basic-auth";
          metadata.labels."cnpg.io/reload" = "true";
          stringData = {
            username = moduleName;
            password = "{{ lillepass }}";
          };
        };
        Cluster.pg0.spec.managed.roles.${moduleName} = {
          login = true;
          passwordSecret.name = "pg0-${moduleName}";
        };
        Database.${moduleName}.spec = {
          name = moduleName;
          owner = moduleName;
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
            name = "admin";
          }
          {
            kind = "Group";
            name = "kubernetes-admin";
          }
        ];
      };
      # Keycloak configuration
      kubernetes.resources.${cfg.namespace} = {
        Secret.${secretName} = {
          stringData = {
            username = moduleName;
            password = "{{ lillepass }}";
          };
        };
        StatefulSet.${moduleName} = {
          metadata.labels = {
            "app.kubernetes.io/name" = moduleName;
          };
          spec = {
            serviceName = "${moduleName}-discovery";
            replicas = 1;
            selector.matchLabels = {
              "app.kubernetes.io/name" = moduleName;
            };
            template = {
              metadata.labels = {
                "app.kubernetes.io/name" = moduleName;
              };
              spec = {
                containers = lib.mkNamedList {
                  ${moduleName} = {
                    image = "quay.io/keycloak/keycloak:${cfg.version}";
                    imagePullPolicy = "Always"; # We want minor updates
                    args = [ "start" ];
                    env = lib.mkNamedList {
                      # Constrain Keycloak memory for lab environment
                      JAVA_OPTS_APPEND.value = "-XX:MinHeapFreeRatio=10 -XX:MaxHeapFreeRatio=20 -XX:G1PeriodicGCInterval=30000";
                      # Credentials
                      KC_BOOTSTRAP_ADMIN_USERNAME.valueFrom.secretKeyRef = {
                        name = secretName;
                        key = "username";
                      };
                      KC_BOOTSTRAP_ADMIN_PASSWORD.valueFrom.secretKeyRef = {
                        name = secretName;
                        key = "password";
                      };
                      # Config
                      KC_METRICS_ENABLED.value = "true";
                      KC_PROXY_HEADERS.value = "xforwarded";
                      KC_HTTP_ENABLED.value = "true";
                      KC_HOSTNAME_STRICT.value = "true";
                      KC_HOSTNAME.value = cfg.hostname;
                      KC_HEALTH_ENABLED.value = "true";
                      # Cache
                      KC_CACHE.value = "ispn";
                      KC_CACHE_EMBEDDED_NETWORK_BIND_ADDRESS.valueFrom = {
                        fieldRef = {
                          fieldPath = "status.podIP";
                        };
                      };
                      # DB
                      KC_DB.value = "postgres"; # Database type
                      KC_DB_URL_HOST.value = "pb0-cluster.cnpg-user";
                      KC_DB_URL_DATABASE.value = moduleName; # dbname
                      KC_DB_USERNAME.valueFrom.secretKeyRef = {
                        name = secretName;
                        key = "username";
                      };
                      KC_DB_PASSWORD.valueFrom.secretKeyRef = {
                        name = secretName;
                        key = "password";
                      };
                    };
                    ports = lib.mkNamedList {
                      http.containerPort = 8080;
                      jgroups.containerPort = 7800;
                      jgroups-fd.containerPort = 57800;
                    };
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
                      requests = {
                        cpu = "100m";
                        memory = "500Mi";
                      };
                    };
                  };
                };
                topologySpreadConstraints = [
                  {
                    maxSkew = 1;
                    topologyKey = "kubernetes.io/hostname";
                    whenUnsatisfiable = "DoNotSchedule";
                    labelSelector.matchLabels."app.kubernetes.io/name" = moduleName;
                  }
                ];
              };
            };
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
                secretName = "${moduleName}-cert";
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
        Service.${moduleName} = {
          metadata.labels = {
            "app.kubernetes.io/name" = moduleName;
          };
          spec = {
            ports = [
              {
                protocol = "TCP";
                port = 8080;
                targetPort = "http";
                name = "http";
              }
            ];
            selector."app.kubernetes.io/name" = moduleName;
            type = "ClusterIP";
          };
        };
        Service."${moduleName}-discovery" = {
          metadata.labels = {
            "app.kubernetes.io/name" = moduleName;
          };
          spec = {
            selector."app.kubernetes.io/name" = moduleName;
            clusterIP = "None";
            type = "ClusterIP";
          };
        };
      };
    };
}
