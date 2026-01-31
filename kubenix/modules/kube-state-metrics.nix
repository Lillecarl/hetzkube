{
  config,
  pkgs,
  lib,
  ...
}:
let
  moduleName = "kube-state-metrics";
  cfg = config.${moduleName};
in
{
  options.${moduleName} = {
    enable = lib.mkEnableOption moduleName;
    version = lib.mkOption {
      type = lib.types.str;
    };
    namespace = lib.mkOption {
      type = lib.types.str;
    };
  };
  config = lib.mkIf cfg.enable {
    kubernetes.resources.none.Namespace.${cfg.namespace} = { };
    kubernetes.resources.${cfg.namespace} = {
      ServiceAccount.kube-state-metrics = {
        metadata = {
          labels = {
            "app.kubernetes.io/component" = "exporter";
            "app.kubernetes.io/name" = "kube-state-metrics";
            "app.kubernetes.io/version" = cfg.version;
          };
        };
        automountServiceAccountToken = false;
      };
      Deployment.kube-state-metrics = {
        metadata = {
          labels = {
            "app.kubernetes.io/component" = "exporter";
            "app.kubernetes.io/name" = "kube-state-metrics";
            "app.kubernetes.io/version" = cfg.version;
          };
        };
        spec = {
          replicas = 1;
          selector = {
            matchLabels = {
              "app.kubernetes.io/name" = "kube-state-metrics";
            };
          };
          template = {
            metadata = {
              labels = {
                "app.kubernetes.io/component" = "exporter";
                "app.kubernetes.io/name" = "kube-state-metrics";
                "app.kubernetes.io/version" = cfg.version;
              };
            };
            spec = {
              automountServiceAccountToken = true;
              containers = [
                {
                  image = "registry.k8s.io/kube-state-metrics/kube-state-metrics:v${cfg.version}";
                  livenessProbe = {
                    httpGet = {
                      path = "/livez";
                      port = "http-metrics";
                    };
                    initialDelaySeconds = 5;
                    timeoutSeconds = 5;
                  };
                  name = "kube-state-metrics";
                  ports = [
                    {
                      containerPort = 8080;
                      name = "http-metrics";
                    }
                    {
                      containerPort = 8081;
                      name = "telemetry";
                    }
                  ];
                  readinessProbe = {
                    httpGet = {
                      path = "/readyz";
                      port = "telemetry";
                    };
                    initialDelaySeconds = 5;
                    timeoutSeconds = 5;
                  };
                  securityContext = {
                    allowPrivilegeEscalation = false;
                    capabilities = {
                      drop = [ "ALL" ];
                    };
                    readOnlyRootFilesystem = true;
                    runAsNonRoot = true;
                    runAsUser = 65534;
                    seccompProfile = {
                      type = "RuntimeDefault";
                    };
                  };
                }
              ];
              nodeSelector = {
                "kubernetes.io/os" = "linux";
              };
              serviceAccountName = "kube-state-metrics";
            };
          };
        };
      };
      Service.kube-state-metrics = {
        metadata = {
          labels = {
            "app.kubernetes.io/component" = "exporter";
            "app.kubernetes.io/name" = "kube-state-metrics";
            "app.kubernetes.io/version" = cfg.version;
          };
        };
        spec = {
          clusterIP = "None";
          ports = [
            {
              name = "http-metrics";
              port = 8080;
              targetPort = "http-metrics";
            }
            {
              name = "telemetry";
              port = 8081;
              targetPort = "telemetry";
            }
          ];
          selector = {
            "app.kubernetes.io/name" = "kube-state-metrics";
          };
        };
      };
      VMServiceScrape.kube-state-metrics = {
        metadata = {
          labels = {
            "app.kubernetes.io/name" = "kube-state-metrics";
          };
        };
        spec = {
          selector = {
            matchLabels = {
              "app.kubernetes.io/name" = "kube-state-metrics";
            };
          };
          endpoints = [
            {
              port = "http-metrics";
              interval = "30s";
              honorLabels = true;
            }
            {
              port = "telemetry";
              interval = "30s";
            }
          ];
        };
      };
    };
    kubernetes.resources.none = {
      ClusterRole.kube-state-metrics = {
        metadata = {
          labels = {
            "app.kubernetes.io/component" = "exporter";
            "app.kubernetes.io/name" = "kube-state-metrics";
            "app.kubernetes.io/version" = cfg.version;
          };
        };
        rules = [
          {
            apiGroups = [ "" ];
            resources = [
              "configmaps"
              "secrets"
              "nodes"
              "pods"
              "services"
              "serviceaccounts"
              "resourcequotas"
              "replicationcontrollers"
              "limitranges"
              "persistentvolumeclaims"
              "persistentvolumes"
              "namespaces"
              "endpoints"
            ];
            verbs = [
              "list"
              "watch"
            ];
          }
          {
            apiGroups = [ "apps" ];
            resources = [
              "statefulsets"
              "daemonsets"
              "deployments"
              "replicasets"
            ];
            verbs = [
              "list"
              "watch"
            ];
          }
          {
            apiGroups = [ "batch" ];
            resources = [
              "cronjobs"
              "jobs"
            ];
            verbs = [
              "list"
              "watch"
            ];
          }
          {
            apiGroups = [ "autoscaling" ];
            resources = [ "horizontalpodautoscalers" ];
            verbs = [
              "list"
              "watch"
            ];
          }
          {
            apiGroups = [ "authentication.k8s.io" ];
            resources = [ "tokenreviews" ];
            verbs = [ "create" ];
          }
          {
            apiGroups = [ "authorization.k8s.io" ];
            resources = [ "subjectaccessreviews" ];
            verbs = [ "create" ];
          }
          {
            apiGroups = [ "policy" ];
            resources = [ "poddisruptionbudgets" ];
            verbs = [
              "list"
              "watch"
            ];
          }
          {
            apiGroups = [ "certificates.k8s.io" ];
            resources = [ "certificatesigningrequests" ];
            verbs = [
              "list"
              "watch"
            ];
          }
          {
            apiGroups = [ "discovery.k8s.io" ];
            resources = [ "endpointslices" ];
            verbs = [
              "list"
              "watch"
            ];
          }
          {
            apiGroups = [ "storage.k8s.io" ];
            resources = [
              "storageclasses"
              "volumeattachments"
            ];
            verbs = [
              "list"
              "watch"
            ];
          }
          {
            apiGroups = [ "admissionregistration.k8s.io" ];
            resources = [
              "mutatingwebhookconfigurations"
              "validatingwebhookconfigurations"
            ];
            verbs = [
              "list"
              "watch"
            ];
          }
          {
            apiGroups = [ "networking.k8s.io" ];
            resources = [
              "networkpolicies"
              "ingressclasses"
              "ingresses"
            ];
            verbs = [
              "list"
              "watch"
            ];
          }
          {
            apiGroups = [ "coordination.k8s.io" ];
            resources = [ "leases" ];
            verbs = [
              "list"
              "watch"
            ];
          }
          {
            apiGroups = [ "rbac.authorization.k8s.io" ];
            resources = [
              "clusterrolebindings"
              "clusterroles"
              "rolebindings"
              "roles"
            ];
            verbs = [
              "list"
              "watch"
            ];
          }
        ];
      };
      ClusterRoleBinding.kube-state-metrics = {
        metadata = {
          labels = {
            "app.kubernetes.io/component" = "exporter";
            "app.kubernetes.io/name" = "kube-state-metrics";
            "app.kubernetes.io/version" = cfg.version;
          };
        };
        roleRef = {
          apiGroup = "rbac.authorization.k8s.io";
          kind = "ClusterRole";
          name = "kube-state-metrics";
        };
        subjects = [
          {
            kind = "ServiceAccount";
            name = "kube-state-metrics";
            namespace = "observability";
          }
        ];
      };
    };
  };
}
