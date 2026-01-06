# See https://github.com/keycloak/keycloak-quickstarts/blob/main/kubernetes/
{
  config,
  lib,
  eso,
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
    hostnames = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      description = "hostnames for ${moduleName}";
    };
    version = lib.mkOption {
      type = lib.types.str;
      description = "${moduleName} version";
      default = "26.5";
    };
  };
  config = lib.mkIf cfg.enable {
    # Enable CNPG
    cnpg.enable = true;
    # Database configuration
    kubernetes.resources.database = {
      ExternalSecret."pg0-keycloak" = eso.mkBasic "name:keycloak-db";
      Cluster.pg0.spec.managed.roles.keycloak = {
        login = true;
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
      ExternalSecret.admin = eso.mkBasic "name:keycloak-admin";
      ExternalSecret.db = eso.mkBasic "name:keycloak-db";
      StatefulSet.keycloak = {
        metadata.labels = {
          "app.kubernetes.io/name" = "keycloak";
        };
        spec = {
          serviceName = "keycloak-discovery";
          replicas = 1;
          selector.matchLabels = {
            "app.kubernetes.io/name" = "keycloak";
          };
          template = {
            metadata.labels = {
              "app.kubernetes.io/name" = "keycloak";
            };
            spec = {
              containers = lib.mkNamedList {
                keycloak = {
                  image = "quay.io/keycloak/keycloak:${cfg.version}";
                  imagePullPolicy = "Always"; # We want minor updates
                  args = [ "start" ];
                  env = lib.mkNamedList {
                    # Constrain Keycloak memory for lab environment
                    JAVA_OPTS_APPEND.value = "-XX:MinHeapFreeRatio=10 -XX:MaxHeapFreeRatio=20 -XX:G1PeriodicGCInterval=30000";
                    # Config
                    KC_METRICS_ENABLED.value = "true";
                    KC_PROXY_HEADERS.value = "xforwarded";
                    KC_HTTP_ENABLED.value = "true";
                    KC_HOSTNAME_STRICT.value = "false";
                    # KC_HOSTNAME.value = cfg.hostname;
                    KC_HEALTH_ENABLED.value = "true";
                    # Cache
                    KC_CACHE.value = "ispn";
                    KC_CACHE_EMBEDDED_NETWORK_BIND_ADDRESS.valueFrom.fieldRef.fieldPath = "status.podIP";
                    # DB
                    KC_DB.value = "postgres"; # Database type
                    KC_DB_URL_HOST.value = "pb0-cluster.database";
                    KC_DB_URL_DATABASE.value = "keycloak"; # dbname
                    # Credentials
                    KC_BOOTSTRAP_ADMIN_USERNAME.valueFrom.secretKeyRef = {
                      name = "admin";
                      key = "username";
                    };
                    KC_BOOTSTRAP_ADMIN_PASSWORD.valueFrom.secretKeyRef = {
                      name = "admin";
                      key = "password";
                    };
                    KC_DB_USERNAME.valueFrom.secretKeyRef = {
                      name = "db";
                      key = "username";
                    };
                    KC_DB_PASSWORD.valueFrom.secretKeyRef = {
                      name = "db";
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
                  labelSelector.matchLabels."app.kubernetes.io/name" = "keycloak";
                }
              ];
            };
          };
        };
      };
      HTTPRoute.keycloak = {
        spec = {
          parentRefs = [
            {
              name = "default";
              namespace = "kube-system";
            }
          ];
          hostnames = cfg.hostnames;
          rules = [
            {
              matches = [
                {
                  path = {
                    type = "PathPrefix";
                    value = "/";
                  };
                }
              ];
              backendRefs = [
                {
                  name = "keycloak";
                  port = 8080;
                }
              ];
            }
          ];
        };
      };
      HTTPRoute.keycloak-redir = {
        spec = {
          parentRefs = [
            {
              name = "default";
              namespace = "kube-system";
            }
          ];
          hostnames = [
            (lib.head cfg.hostnames)
          ];
          rules = [
            {
              matches = [
                {
                  path = {
                    type = "Exact";
                    value = "/";
                  };
                }
              ];
              filters = [
                {
                  type = "RequestRedirect";
                  requestRedirect = {
                    path = {
                      type = "ReplaceFullPath";
                      replaceFullPath = "/realms/auth/account";
                    };
                    statusCode = 302;
                  };
                }
              ];
            }
          ];
        };
      };
      Service.keycloak = {
        metadata.labels = {
          "app.kubernetes.io/name" = "keycloak";
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
          selector."app.kubernetes.io/name" = "keycloak";
          type = "ClusterIP";
        };
      };
      Service.keycloak-discovery = {
        metadata.labels = {
          "app.kubernetes.io/name" = "keycloak";
        };
        spec = {
          selector."app.kubernetes.io/name" = "keycloak";
          clusterIP = "None";
          type = "ClusterIP";
        };
      };
    };
  };
}
