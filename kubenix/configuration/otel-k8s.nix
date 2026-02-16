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
          pkgs.bash
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
            {
              apiGroups = [ "events.k8s.io" ];
              resources = [ "events" ];
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
                k8sobjects:
                  auth_type: serviceAccount
                  objects:
                    - name: events
                      mode: "watch"
                      group: "events.k8s.io"
                      exclude_watch_type:
                        - "DELETED"

              processors:
                k8sattributes:
                  passthrough: false
                  pod_association:
                    - sources:
                        - from: resource_attribute
                          name: k8s.pod.ip
                    - sources:
                        - from: resource_attribute
                          name: k8s.pod.uid
                    - sources:
                        - from: connection
                  extract:
                    otel_annotations: true
                    metadata:
                      - k8s.namespace.name
                      - k8s.pod.name
                      - k8s.pod.uid
                      - k8s.node.name
                      - k8s.pod.start_time
                      - k8s.deployment.name
                      - k8s.replicaset.name
                      - k8s.replicaset.uid
                      - k8s.daemonset.name
                      - k8s.daemonset.uid
                      - k8s.job.name
                      - k8s.job.uid
                      - k8s.container.name
                      - k8s.cronjob.name
                      - k8s.statefulset.name
                      - k8s.statefulset.uid
                      - container.image.tag
                      - container.image.name
                transform:
                  log_statements:
                    - context: log
                      statements:
                        - set(body["_msg"], body["object"]["note"])

              exporters:
                debug:
                  verbosity: detailed
                otlphttp:
                  logs_endpoint: http://vlsingle-logs:9428/insert/opentelemetry/v1/logs

              extensions:
                health_check:
                  endpoint: :13133

              service:
                telemetry:
                  logs:
                    level: debug
                extensions: [health_check]
                pipelines:
                  logs:
                    receivers: [k8sobjects]
                    processors: [k8sattributes, transform]
                    exporters: [debug, otlphttp]
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
                      "--config=file:/etc/otel-collector/config.yaml"
                    ];

                    env = [
                      {
                        name = "PATH";
                        value = "/nix/var/result/bin";
                      }
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
