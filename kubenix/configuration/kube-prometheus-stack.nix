{
  config,
  pkgs,
  lib,
  eso,
  ...
}:
{
  config =
    let
      grafanaHostname = "grafana.lillecarl.com";
    in
    lib.mkIf (config.stage == "full") {
      kubernetes.resources.none.Namespace.observability = { };
      kubernetes.resources.observability = {
        ExternalSecret.pg0-grafana = eso.mkBasic "name:grafana-db";
        ExternalSecret.grafana-admin = eso.mkBasic "name:grafana-admin";
        ExternalSecret.grafana-oidc = eso.mkOpaque "name:keycloak-grafana" "client-secret";
        ExternalSecret.mailgun = eso.mkBasic "name:mailgun-system";
      };
      kubernetes.resources.database = {
        ExternalSecret.pg0-grafana = eso.mkBasic "name:grafana-db";
        Cluster.pg0.spec.managed.roles.grafana = {
          login = true;
          passwordSecret.name = "pg0-grafana";
        };
        Database.grafana.spec = {
          name = "grafana";
          owner = "grafana";
          cluster.name = "pg0";
          databaseReclaimPolicy = "delete";
        };
      };

      kube-prometheus-stack = {
        enable = true;

        namespace = "observability";
        version = "80.13.3";
        sha256 = "sha256-49y/S3Awbv9wDZhovJYO42xt3qj83j+29skx5xF6VVQ=";

        helmValues = {
          prometheusOperator = {
            enabled = true;
            # Installs CRDs: ServiceMonitor, PodMonitor, Prometheus, AlertManager, PrometheusRule, etc.
          };

          kube-state-metrics = {
            enabled = true;
            # Single Deployment, exports cluster state metrics
          };

          prometheus-node-exporter = {
            enabled = true;
            hostNetwork = true;
            hostPID = true;
            # DaemonSet on every node for hardware/OS metrics
          };

          prometheus = {
            enabled = true;
            prometheusSpec = {
              retention = "10d";
              storageSpec = {
                volumeClaimTemplate = {
                  spec = {
                    storageClassName = "hcloud-volumes";
                    accessModes = [ "ReadWriteOnce" ];
                    resources = {
                      requests = {
                        storage = "10Gi";
                      };
                    };
                  };
                };
              };
              # ServiceMonitor selection - scrape everything in this namespace
              serviceMonitorSelectorNilUsesHelmValues = false;
              podMonitorSelectorNilUsesHelmValues = false;
            };
          };

          alertmanager = {
            enabled = true;
            alertmanagerSpec = {
              storage = {
                volumeClaimTemplate = {
                  spec = {
                    storageClassName = "hcloud-volumes";
                    accessModes = [ "ReadWriteOnce" ];
                    resources = {
                      requests = {
                        storage = "10Gi";
                      };
                    };
                  };
                };
              };
            };
          };

          grafana = {
            enabled = true;

            # Admin credentials (fallback when OIDC unavailable)
            admin = {
              existingSecret = "grafana-admin";
              userKey = "username";
              passwordKey = "password";
            };

            # Persistence for plugins
            persistence = {
              enabled = true;
              storageClassName = "hcloud-volumes";
              size = "10Gi";
            };

            "grafana.ini" = {
              server = {
                root_url = "https://${grafanaHostname}";
              };

              # Keycloak OIDC
              "auth.generic_oauth" = {
                enabled = true;
                name = "Keycloak";
                allow_sign_up = true;
                client_id = "grafana";
                client_secret = "$__file{/etc/secrets/oidc/client-secret}";
                scopes = "openid profile email";
                auth_url = "https://${lib.head config.keycloak.hostnames}/realms/master/protocol/openid-connect/auth";
                token_url = "https://${lib.head config.keycloak.hostnames}/realms/master/protocol/openid-connect/token";
                api_url = "https://${lib.head config.keycloak.hostnames}/realms/master/protocol/openid-connect/userinfo";
                role_attribute_path = "contains(realm_access.roles[*], 'admin') && 'Admin' || contains(realm_access.roles[*], 'editor') && 'Editor' || 'Viewer'";
              };
              database = {
                type = "postgres";
                host = "pb0-cluster.database.svc.cluster.local:5432";
                name = "grafana";
                user = "$__file{/etc/secrets/db/username}";
                password = "$__file{/etc/secrets/db/password}";
              };
            };

            # Mount OIDC secret
            extraSecretMounts = [
              {
                name = "oidc-secret";
                secretName = "grafana-oidc";
                defaultMode = 288; # 0440 in octal = 288 in decimal
                mountPath = "/etc/secrets/oidc";
                readOnly = true;
              }
              {
                name = "db-creds";
                secretName = "pg0-grafana";
                defaultMode = 288;
                mountPath = "/etc/secrets/db";
                readOnly = true;
              }
            ];

            route = lib.mkIf true {
              main = {
                enabled = true;
                apiVersion = "gateway.networking.k8s.io/v1";
                kind = "HTTPRoute";
                hostnames = [ grafanaHostname ];
                parentRefs = [
                  {
                    name = "default";
                    namespace = "kube-system";
                  }
                ];
              };
            };

            # Datasources
            datasources = {
              "datasources.yaml" = {
                apiVersion = 1;
                datasources = [
                  {
                    name = "Prometheus";
                    type = "prometheus";
                    url = "http://kube-prometheus-stack-prometheus.monitoring.svc.cluster.local:9090";
                    access = "proxy";
                    isDefault = true;
                  }
                ];
              };
            };
          };

          # Default ServiceMonitors and alerting rules
          defaultRules = {
            create = true;
            rules = {
              alertmanager = true;
              etcd = true;
              configReloaders = true;
              general = true;
              k8s = true;
              kubeApiserverAvailability = true;
              kubeApiserverBurnrate = true;
              kubeApiserverHistogram = true;
              kubeApiserverSlos = true;
              kubeControllerManager = true;
              kubelet = true;
              kubeProxy = true;
              kubePrometheusGeneral = true;
              kubePrometheusNodeRecording = true;
              kubernetesApps = true;
              kubernetesResources = true;
              kubernetesStorage = true;
              kubernetesSystem = true;
              kubeSchedulerAlerting = true;
              kubeSchedulerRecording = true;
              kubeStateMetrics = true;
              network = true;
              node = true;
              nodeExporterAlerting = true;
              nodeExporterRecording = true;
              prometheus = true;
              prometheusOperator = true;
            };
          };

          # ServiceMonitors for Kubernetes components
          kubeApiServer = {
            enabled = true;
          };

          kubelet = {
            enabled = true;
          };

          kubeControllerManager = {
            enabled = true;
          };

          coreDns = {
            enabled = true;
          };

          kubeEtcd = {
            enabled = true;
          };

          kubeScheduler = {
            enabled = true;
          };

          kubeProxy = {
            enabled = false; # Disabled - using Cilium
          };
        };
      };
    };
}
