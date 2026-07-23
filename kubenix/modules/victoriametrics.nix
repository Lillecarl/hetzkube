{
  config,
  pkgs,
  lib,
  hlib,
  ...
}:
let
  moduleName = "victoriametrics";
  cfg = config.${moduleName};
  namespace = "vm";
in
{
  options.${moduleName} = {
    enable = lib.mkEnableOption moduleName;
    operator = {
      enable = lib.mkEnableOption moduleName;
      version = lib.mkOption {
        type = lib.types.nonEmptyStr;
      };
    };
    metrics = {
      enable = lib.mkEnableOption moduleName;
      promCRD = lib.mkEnableOption "prometheus CRDs";
      namespace = lib.mkOption {
        type = lib.types.nonEmptyStr;
      };
    };
    logs = {
      enable = lib.mkEnableOption moduleName;
      namespace = lib.mkOption {
        type = lib.types.nonEmptyStr;
      };
      version = lib.mkOption {
        type = lib.types.str;
      };
    };
    alertmanager = {
      enable = lib.mkEnableOption "VMAlertmanager, notified by both VMAlert instances";
      telegram = {
        chatId = lib.mkOption {
          type = lib.types.int;
          description = "Telegram chat ID alerts are delivered to.";
        };
        scalewaySecret = lib.mkOption {
          type = lib.types.nonEmptyStr;
          default = "name:telegram-bot-token";
          description = "Scaleway secret (fetched via ESO) holding the Telegram bot token.";
        };
      };
    };
  };
  config = lib.mkIf cfg.enable {
    importyaml = lib.mkMerge [
      (lib.mkIf cfg.operator.enable {
        vm-operator = lib.mkIf cfg.operator.enable {
          src = "https://github.com/VictoriaMetrics/operator/releases/download/v${cfg.operator.version}/install-with-webhook.yaml";
          convertLists = false;
        };
      })
      (
        let
          repo = builtins.fetchTree {
            type = "github";
            owner = "prometheus-operator";
            repo = "prometheus-operator";
          };
          src = "${repo}/example/prometheus-operator-crd-full";
        in
        lib.mkIf cfg.metrics.promCRD (
          lib.pipe (lib.filesystem.listFilesRecursive src) [
            (lib.map (path: {
              name = builtins.unsafeDiscardStringContext (lib.baseNameOf path);
              value.src = path;
            }))
            lib.listToAttrs
          ]
        )
      )
    ];
    kubernetes.objects = lib.mkMerge [
      (lib.mkIf cfg.metrics.enable {
        ${cfg.metrics.namespace} = {
          VMSingle.metrics = {
            spec = {
              retentionPeriod = "1d";
              replicaCount = 1;
              storage = {
                accessModes = [ "ReadWriteOnce" ];
                resources = {
                  requests = {
                    storage = "10Gi";
                  };
                };
              };
              resources = {
                requests = {
                  cpu = "250m";
                  memory = "256Mi";
                };
              };
            };
          };
          VMAgent.metrics-ingest = {
            spec = {
              externalLabels = {
                cluster = config.clusterName;
              };
              replicaCount = 1;
              remoteWrite = [
                {
                  url = "http://vmsingle-metrics:8429/api/v1/write";
                }
              ];
              selectAllByDefault = true;

              serviceScrapeSelector = { };
              podScrapeSelector = { };
              nodeScrapeSelector = { };
              # Exclude static scrapes - they're handled by metrics-control-plane with daemonSetMode
              staticScrapeSelector = {
                matchExpressions = [
                  {
                    key = "role";
                    operator = "DoesNotExist";
                  }
                ];
              };
              podScrapeNamespaceSelector = { };
              serviceScrapeNamespaceSelector = { };
              nodeScrapeNamespaceSelector = { };
              staticScrapeNamespaceSelector = { };

              resources = {
                requests = {
                  cpu = "250m";
                  memory = "128Mi";
                };
              };
            };
          };

          VMAgent.metrics-control-plane = {
            spec = {
              externalLabels = {
                cluster = config.clusterName;
              };
              daemonSetMode = true;
              remoteWrite = [
                {
                  url = "http://vmsingle-metrics:8429/api/v1/write";
                }
              ];

              serviceScrapeSelector = { };
              podScrapeSelector = { };
              nodeScrapeSelector = { };
              podScrapeNamespaceSelector = { };
              serviceScrapeNamespaceSelector = { };
              nodeScrapeNamespaceSelector = { };

              nodeSelector = {
                "node-role.kubernetes.io/control-plane" = "";
              };

              tolerations = [
                {
                  key = "node-role.kubernetes.io/control-plane";
                  operator = "Exists";
                  effect = "NoSchedule";
                }
              ];

              hostNetwork = true;
              dnsPolicy = "ClusterFirstWithHostNet";

              inlineScrapeConfig = ''
                - job_name: kube-scheduler
                  static_configs:
                    - targets: ["127.0.0.1:10259"]
                  scheme: https
                  tls_config:
                    insecure_skip_verify: true
                  bearer_token_file: /var/run/secrets/kubernetes.io/serviceaccount/token
                  metrics_path: /metrics
                  scrape_interval: 30s

                - job_name: kube-controller-manager
                  static_configs:
                    - targets: ["127.0.0.1:10257"]
                  scheme: https
                  tls_config:
                    insecure_skip_verify: true
                  bearer_token_file: /var/run/secrets/kubernetes.io/serviceaccount/token
                  metrics_path: /metrics
                  scrape_interval: 30s

                - job_name: etcd
                  static_configs:
                    - targets: ["127.0.0.1:2381"]
                  scheme: http
                  metrics_path: /metrics
                  scrape_interval: 30s
              '';

              resources = {
                requests = {
                  cpu = "250m";
                  memory = "128Mi";
                };
              };
            };
          };
          VMAlert.metrics = {
            spec = {
              # The address of your VictoriaMetrics storage (e.g., vmselect or single-node)
              datasource.url = "http://vmsingle-metrics:8429";

              # Where to write the calculated recording rules back to
              remoteWrite.url = "http://vmsingle-metrics:8429";

              # This selector must match the labels on your VMRule objects
              ruleSelector = {
                matchLabels = {
                  role = "metrics";
                };
              };

              evaluationInterval = "30s";

              notifiers = lib.optional cfg.alertmanager.enable {
                url = "http://vmalertmanager-alertmanager.${cfg.metrics.namespace}.svc:9093";
              };
            };
          };

          VMServiceScrape = {
            kubernetes = {
              spec = {
                jobLabel = "component";
                selector = {
                  matchLabels = {
                    component = "apiserver";
                  };
                };
                namespaceSelector = {
                  matchNames = [ "default" ];
                };
                endpoints = [
                  {
                    port = "https";
                    scheme = "https";
                    tlsConfig = {
                      caFile = "/var/run/secrets/kubernetes.io/serviceaccount/ca.crt";
                      serverName = "kubernetes";
                    };
                    bearerTokenFile = "/var/run/secrets/kubernetes.io/serviceaccount/token";
                    relabelConfigs = [
                      {
                        action = "replace";
                        replacement = "kube-apiserver";
                        targetLabel = "job";
                      }
                    ];
                  }
                ];
              };
            };
            coredns = {
              spec = {
                jobLabel = "k8s-app";
                selector = {
                  matchLabels = {
                    k8s-app = "coredns";
                  };
                };
                namespaceSelector = {
                  matchNames = [ "kube-system" ];
                };
                endpoints = [
                  {
                    port = "http-metrics";
                    scheme = "http";
                  }
                ];
              };
            };
          };
          VMNodeScrape.cadvisor = {
            spec = {
              scheme = "https";
              tlsConfig = {
                insecureSkipVerify = true;
              };
              bearerTokenFile = "/var/run/secrets/kubernetes.io/serviceaccount/token";
              path = "/metrics/cadvisor";
              port = "10250";
              interval = "30s";
              relabelConfigs = [
                {
                  action = "replace";
                  sourceLabels = [ "__meta_kubernetes_node_name" ];
                  targetLabel = "node";
                }
                {
                  action = "replace";
                  replacement = "cadvisor";
                  targetLabel = "job";
                }
              ];
            };
          };
          VMNodeScrape.kubelet = {
            spec = {
              scheme = "https";
              tlsConfig = {
                insecureSkipVerify = true;
              };
              bearerTokenFile = "/var/run/secrets/kubernetes.io/serviceaccount/token";
              path = "/metrics";
              port = "10250";
              interval = "30s";
              relabelConfigs = [
                {
                  action = "replace";
                  sourceLabels = [ "__meta_kubernetes_node_name" ];
                  targetLabel = "node";
                }
                {
                  action = "replace";
                  replacement = "kubelet";
                  targetLabel = "job";
                }
              ];
            };
          };
        };
      })

      (lib.mkIf cfg.logs.enable {
        ${cfg.logs.namespace} = {
          VLSingle.logs = {
            spec = {
              retentionPeriod = "71";
              storage = {
                accessModes = [ "ReadWriteOnce" ];
                resources = {
                  requests = {
                    storage = "10Gi";
                  };
                };
              };
              resources = {
                requests = {
                  cpu = "250m";
                  memory = "256Mi";
                };
              };
            };
          };
          VLAgent.logs-ingest = {
            spec = {
              remoteWrite = [
                {
                  url = "http://vlsingle-logs:9428/insert/native";
                }
              ];
              k8sCollector = {
                enabled = true;
                extraFields = lib.toJSON { cluster = config.clusterName; };
              };
              tolerations = [
                {
                  key = "node-role.kubernetes.io/control-plane";
                  operator = "Exists";
                  effect = "NoSchedule";
                }
              ];
              resources = {
                requests = {
                  cpu = "250m";
                  memory = "128Mi";
                };
              };
            };
          };
          VMAlert.logs = {
            spec = {
              datasource.url = "http://vlsingle-logs:9428/select/logsql/query";

              remoteWrite.url = "http://vmsingle-metrics:8429";

              ruleSelector = {
                matchLabels = {
                  role = "logs";
                };
              };

              evaluationInterval = "30s";

              notifiers = lib.optional cfg.alertmanager.enable {
                url = "http://vmalertmanager-alertmanager.${cfg.metrics.namespace}.svc:9093";
              };
            };
          };
        };
      })

      (lib.mkIf cfg.alertmanager.enable {
        ${cfg.metrics.namespace} = {
          # Bot token lives in Scaleway (ESO), never in git -- chat_id isn't
          # secret-shaped in the CRD (plain integer), so it's a Nix option.
          ExternalSecret.telegram = hlib.eso.mkToken cfg.alertmanager.telegram.scalewaySecret;
          VMAlertmanager.alertmanager = {
            spec = {
              replicaCount = 1;
              port = "9093";
              selectAllByDefault = true;
              configSelector = { };
              configNamespaceSelector = { };
              # Without this, the operator auto-injects a `namespace =
              # "<config's own namespace>"` matcher on every route derived
              # from a VMAlertmanagerConfig -- since almost all cluster-health
              # alerts (node/kubelet/scheduler/etc) come from cluster-scoped
              # or other-namespace resources, that would silently swallow
              # nearly everything into the default route instead of Telegram.
              disableNamespaceMatcher = true;
              storage.volumeClaimTemplate.spec = {
                accessModes = [ "ReadWriteOnce" ];
                resources = {
                  requests = {
                    storage = "1Gi";
                  };
                };
              };
              resources = {
                requests = {
                  cpu = "50m";
                  memory = "64Mi";
                };
              };
            };
          };
          VMAlertmanagerConfig.telegram = {
            spec = {
              route = {
                receiver = "telegram";
                group_by = [
                  "namespace"
                  "alertname"
                ];
                group_wait = "30s";
                group_interval = "5m";
                repeat_interval = "4h";
              };
              receivers = [
                {
                  name = "telegram";
                  telegram_configs = [
                    {
                      chat_id = cfg.alertmanager.telegram.chatId;
                      bot_token = {
                        name = "telegram";
                        key = "token";
                      };
                    }
                  ];
                }
              ];
            };
          };
        };
      })
    ];
  };
}
