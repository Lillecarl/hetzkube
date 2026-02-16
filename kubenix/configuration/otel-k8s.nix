{
  config,
  pkgs,
  lib,
  ...
}:
{
  config =
    let
      namespace = "observability";

      labels = {
        "app.kubernetes.io/name" = "otel-collector";
        "app.kubernetes.io/component" = "k8s-events";
      };

      # Minimal environment for debugging
      container-env = pkgs.buildEnv {
        name = "otel-collector-env";
        paths = [
          pkgs.fishMinimal
          pkgs.coreutils
        ];
      };

    in
    lib.mkIf (config.stage == "full") {
      kubernetes.resources.none = {
        ClusterRole.otel-collector = {
          metadata.labels = labels;
          rules = [
            {
              apiGroups = [ "" ];
              resources = [
                "events"
                "namespaces"
                "namespaces/status"
                "nodes"
                "nodes/spec"
                "pods"
                "pods/status"
                "replicationcontrollers"
                "replicationcontrollers/status"
                "resourcequotas"
                "services"
              ];
              verbs = [
                "get"
                "list"
                "watch"
              ];
            }
            {
              apiGroups = [ "apps" ];
              resources = [
                "daemonsets"
                "deployments"
                "replicasets"
                "statefulsets"
              ];
              verbs = [
                "get"
                "list"
                "watch"
              ];
            }
            {
              apiGroups = [ "extensions" ];
              resources = [
                "daemonsets"
                "deployments"
                "replicasets"
              ];
              verbs = [
                "get"
                "list"
                "watch"
              ];
            }
            {
              apiGroups = [ "batch" ];
              resources = [
                "jobs"
                "cronjobs"
              ];
              verbs = [
                "get"
                "list"
                "watch"
              ];
            }
            {
              apiGroups = [ "autoscaling" ];
              resources = [ "horizontalpodautoscalers" ];
              verbs = [
                "get"
                "list"
                "watch"
              ];
            }
          ];
        };

        ClusterRoleBinding.otel-collector = {
          metadata.labels = labels;
          roleRef = {
            apiGroup = "rbac.authorization.k8s.io";
            kind = "ClusterRole";
            name = "otel-collector";
          };
          subjects = [
            {
              kind = "ServiceAccount";
              name = "otel-collector";
              namespace = namespace;
            }
          ];
        };
      };

      kubernetes.resources.${namespace} = {
        ServiceAccount.otel-collector = {
          metadata.labels = labels;
        };

        ConfigMap.otel-collector = {
          metadata.labels = labels;
          data."config.yaml" = # yaml
            ''
              receivers:
                k8s_events:
                  auth_type: serviceAccount

              exporters:
                otlphttp:
                  logs_endpoint: http://vlsingle-logs:9428/insert/opentelemetry/v1/logs

              extensions:
                health_check:
                  endpoint: :13133

              service:
                extensions: [health_check]
                pipelines:
                  logs:
                    receivers: [k8s_events]
                    exporters: [otlphttp]
            '';
        };

        Deployment.otel-collector = {
          metadata.labels = labels;
          spec = {
            replicas = 1;
            selector.matchLabels = labels;
            template = {
              metadata.labels = labels;
              metadata.annotations.configHash = lib.hashAttrs config.kubernetes.resources.${namespace}.ConfigMap.otel-collector.data;
              spec = {
                nodeSelector."kubernetes.io/arch" = "amd64";
                serviceAccountName = "otel-collector";
                containers = lib.mkNamedList {
                  otel-collector = {
                    image = "gcr.io/distroless/static:latest";
                    command = [
                      (lib.getExe pkgs.tini)
                      "--"
                      (lib.getExe pkgs.opentelemetry-collector-releases.otelcol-k8s)
                    ];
                    args = [
                      "--config=/etc/otel-collector/config.yaml"
                    ];

                    ports = lib.mkNamedList {
                      metrics = {
                        name = "metrics";
                        containerPort = 8888;
                      };
                      health = {
                        name = "health";
                        containerPort = 13133;
                      };
                    };

                    livenessProbe = {
                      httpGet = {
                        path = "/";
                        port = "health";
                      };
                      initialDelaySeconds = 5;
                      periodSeconds = 10;
                    };

                    readinessProbe = {
                      httpGet = {
                        path = "/";
                        port = "health";
                      };
                      initialDelaySeconds = 5;
                      periodSeconds = 10;
                    };

                    volumeMounts = [
                      {
                        name = "config";
                        mountPath = "/etc/otel-collector";
                        readOnly = true;
                      }
                      {
                        name = "nix-store";
                        mountPath = "/nix";
                        subPath = "nix";
                        readOnly = true;
                      }
                    ];

                    resources = {
                      requests = {
                        cpu = "50m";
                        memory = "32Mi";
                      };
                      limits = {
                        memory = "512Mi";
                      };
                    };
                  };
                };

                volumes = lib.mkNamedList {
                  config.configMap = {
                    name = "otel-collector";
                  };
                  nix-store.csi = {
                    driver = "nix.csi.store";
                    readOnly = true;
                    volumeAttributes.${pkgs.stdenv.hostPlatform.system} = container-env;
                  };
                };
              };
            };
          };
        };

        Service.otel-collector = {
          metadata.labels = labels;
          spec = {
            type = "ClusterIP";
            selector = labels;
            ports = lib.mkNamedList {
              metrics = {
                name = "metrics";
                port = 8888;
                targetPort = "metrics";
                protocol = "TCP";
              };
            };
          };
        };
      };
    };
}
