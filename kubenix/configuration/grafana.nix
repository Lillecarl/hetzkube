{
  config,
  lib,
  hlib,
  ...
}:
let
  grafanaHostname = "grafana.lillecarl.com";
in
{
  config = lib.mkIf (config.stage == "full") {
    kubernetes.resources.observability = {
      # ExternalSecrets
      ExternalSecret.pg0-grafana = hlib.eso.mkBasic "name:grafana-db";
      ExternalSecret.grafana-admin = hlib.eso.mkBasic "name:grafana-admin";
      ExternalSecret.grafana-oidc = hlib.eso.mkOpaque "name:keycloak-grafana" "client-secret";

      # Grafana Instance using v1beta1 schema
      Grafana.grafana = {
        metadata.labels.dashboards = "grafana";
        spec = {
          # grafana.ini configuration
          config = {
            server = {
              root_url = "https://${grafanaHostname}";
            };
            database = {
              type = "postgres";
              host = "pg0-rw.database.svc.cluster.local:5432";
              name = "grafana";
              user = "$__file{/etc/secrets/db/username}";
              password = "$__file{/etc/secrets/db/password}";
            };
            "auth.generic_oauth" = {
              enabled = "true";
              name = "Keycloak";
              allow_sign_up = "true";
              client_id = "grafana";
              client_secret = "$__file{/etc/secrets/oidc/client-secret}";
              use_pkce = "true";
              scopes = "openid profile email";
              auth_url = "https://${lib.head config.keycloak.hostnames}/realms/auth/protocol/openid-connect/auth";
              token_url = "https://${lib.head config.keycloak.hostnames}/realms/auth/protocol/openid-connect/token";
              api_url = "https://${lib.head config.keycloak.hostnames}/realms/auth/protocol/openid-connect/userinfo";
              role_attribute_path = "contains(realm_access.roles[*], 'admin') && 'Admin' || contains(realm_access.roles[*], 'editor') && 'Editor' || 'Viewer'";
            };
          };
          # Deployment customization for secrets and volumes
          deployment = {
            spec = {
              template = {
                spec = {
                  # Added securityContext to allow the Grafana user (472) to read secrets
                  securityContext = {
                    fsGroup = 472;
                    runAsGroup = 472;
                    runAsUser = 472;
                  };
                  containers = [
                    {
                      name = "grafana";
                      volumeMounts = [
                        {
                          name = "oidc-secret";
                          mountPath = "/etc/secrets/oidc";
                          readOnly = true;
                        }
                        {
                          name = "db-creds";
                          mountPath = "/etc/secrets/db";
                          readOnly = true;
                        }
                      ];
                      env = [
                        {
                          name = "GF_INSTALL_PLUGINS";
                          value = "victoriametrics-logs-datasource,victoriametrics-metrics-datasource";
                        }
                      ];
                    }
                  ];
                  volumes = [
                    {
                      name = "oidc-secret";
                      secret = {
                        secretName = "grafana-oidc";
                        # Changed defaultMode to 420 (0644 octal) for broader read access
                        defaultMode = 420;
                      };
                    }
                    {
                      name = "db-creds";
                      secret = {
                        secretName = "pg0-grafana";
                        # Changed defaultMode to 420 (0644 octal)
                        defaultMode = 420;
                      };
                    }
                  ];
                };
              };
            };
          };

          # Persistence
          persistentVolumeClaim = {
            spec = {
              accessModes = [ "ReadWriteOnce" ];
              storageClassName = "hcloud-volumes";
              resources = {
                requests = {
                  storage = "10Gi";
                };
              };
            };
          };

          # Gateway API Integration
          httpRoute = {
            spec = {
              parentRefs = [
                {
                  name = "default";
                  namespace = "kube-system";
                }
              ];
              hostnames = [ grafanaHostname ];
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
                      name = "grafana-service";
                      port = 3000;
                    }
                  ];
                }
              ];
            };
          };
        };
      };

      # VictoriaMetrics Datasource
      GrafanaDatasource.vmsingle-prom = {
        spec = {
          instanceSelector.matchLabels.dashboards = "grafana";
          datasource = {
            name = "Prometheus";
            type = "prometheus";
            url = "http://vmsingle-metrics.observability.svc.cluster.local:8429";
            access = "proxy";
            isDefault = true;
          };
        };
      };
      # VictoriaMetrics Datasource using the specialized plugin
      GrafanaDatasource.vmsingle-vm = {
        spec = {
          instanceSelector.matchLabels.dashboards = "grafana";
          datasource = {
            name = "VictoriaMetrics";
            type = "victoriametrics-metrics-datasource";
            url = "http://vmsingle-metrics.observability.svc.cluster.local:8429";
            access = "proxy";
          };
        };
      };

      # Alertmanager Datasource -- lets Grafana's own Alerting UI browse and
      # silence alerts from vmalert's VMAlertmanager. Alerting logic itself
      # stays entirely in vmalert/VMRule, so Grafana must never manage its
      # own alert rules against this instance.
      GrafanaDatasource.alertmanager = {
        spec = {
          instanceSelector.matchLabels.dashboards = "grafana";
          datasource = {
            name = "Alertmanager";
            type = "alertmanager";
            url = "http://vmalertmanager-alertmanager.observability.svc.cluster.local:9093";
            access = "proxy";
            isDefault = true;
            jsonData = {
              implementation = "prometheus";
              handleGrafanaManagedAlerts = false;
            };
          };
        };
      };

      # VictoriaLogs Datasource
      GrafanaDatasource.vlsingle = {
        spec = {
          instanceSelector.matchLabels.dashboards = "grafana";
          datasource = {
            name = "VictoriaLogs";
            type = "victoriametrics-logs-datasource";
            url = "http://vlsingle-logs.observability.svc.cluster.local:9428";
            access = "proxy";
          };
        };
      };
    };

    # Database provisioning
    kubernetes.resources.database = {
      ExternalSecret.pg0-grafana = hlib.eso.mkBasic "name:grafana-db";
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
  };
}
