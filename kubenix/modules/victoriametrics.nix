{
  config,
  pkgs,
  lib,
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
  };
  config = lib.mkIf cfg.enable {
    importyaml = lib.mkMerge [
      ({
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
              staticScrapeSelector = { };
              resources = {
                requests = {
                  cpu = "250m";
                  memory = "128Mi";
                };
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
                  }
                ];
              };
            };
            coredns = {
              spec = {
                jobLabel = "k8s-app";
                selector = {
                  matchLabels = {
                    k8s-app = "kube-dns";
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
                extraFields = lib.toJSON { cluster = "hetzkube"; };
              };
              resources = {
                requests = {
                  cpu = "250m";
                  memory = "128Mi";
                };
              };
            };
          };
        };
      })
    ];
  };
}
