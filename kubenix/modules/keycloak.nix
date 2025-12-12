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
      secretName = "keycloak";
    in
    lib.mkIf cfg.enable {
      # Enable CNPG
      cnpg.enable = true;
      # Database configuration
      kubernetes.resources.cnpg-user = {
        Secret.bw-auth-token.stringData.token = "{{ bwtoken }}";
        BitwardenSecret."pg0-${moduleName}" = {
          spec = {
            organizationId = "a5c85a84-042e-44b8-a07e-b16f00119301";
            secretName = "pg0-${moduleName}";
            map = [
              {
                bwSecretId = "3bc9a57c-ba90-47d2-9aa7-b3b100ceffce";
                secretKeyName = "username";
              }
              {
                bwSecretId = "94cb9a4a-6974-4ab1-955c-b3b100cf20d2";
                secretKeyName = "password";
              }
            ];
            authToken = {
              secretName = "bw-auth-token";
              secretKey = "token";
            };
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
        Secret.bw-auth-token.stringData.token = "{{ bwtoken }}";
        BitwardenSecret.${secretName} = {
          spec = {
            organizationId = "a5c85a84-042e-44b8-a07e-b16f00119301";
            secretName = secretName;
            map = [
              {
                bwSecretId = "57336e5d-0602-492e-b4aa-b3b100cf3cf5";
                secretKeyName = "KC_BOOTSTRAP_ADMIN_USERNAME";
              }
              {
                bwSecretId = "3b3656e6-e064-4259-b1bb-b3b100cf551e";
                secretKeyName = "KC_BOOTSTRAP_ADMIN_PASSWORD";
              }
              {
                bwSecretId = "3bc9a57c-ba90-47d2-9aa7-b3b100ceffce";
                secretKeyName = "KC_DB_USERNAME";
              }
              {
                bwSecretId = "94cb9a4a-6974-4ab1-955c-b3b100cf20d2";
                secretKeyName = "KC_DB_PASSWORD";
              }
            ];
            authToken = {
              secretName = "bw-auth-token";
              secretKey = "token";
            };
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
                      # Config
                      KC_METRICS_ENABLED.value = "true";
                      KC_PROXY_HEADERS.value = "xforwarded";
                      KC_HTTP_ENABLED.value = "true";
                      KC_HOSTNAME_STRICT.value = "true";
                      KC_HOSTNAME.value = cfg.hostname;
                      KC_HEALTH_ENABLED.value = "true";
                      # Cache
                      KC_CACHE.value = "ispn";
                      KC_CACHE_EMBEDDED_NETWORK_BIND_ADDRESS.valueFrom.fieldRef.fieldPath = "status.podIP";
                      # DB
                      KC_DB.value = "postgres"; # Database type
                      KC_DB_URL_HOST.value = "pb0-cluster.cnpg-user";
                      KC_DB_URL_DATABASE.value = moduleName; # dbname
                    };
                    envFrom = [ { secretRef.name = secretName; } ];
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
