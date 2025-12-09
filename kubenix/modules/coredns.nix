{
  config,
  pkgs,
  lib,
  ...
}:
let
  moduleName = "coredns";
  cfg = config.${moduleName};
in
{
  options.${moduleName} = {
    enable = lib.mkEnableOption moduleName;
    namespace = lib.mkOption {
      type = lib.types.str;
      default = "kube-system";
    };
    version = lib.mkOption {
      type = lib.types.str;
      default = "1.13.1";
    };
    replicas = lib.mkOption {
      type = lib.types.numbers.positive;
      default = 2;
    };
  };
  config = lib.mkIf cfg.enable {
    kubernetes.resources.none = {
      Namespace.${cfg.namespace} = { };
      ClusterRole.coredns = {
        rules = [
          {
            apiGroups = [ "" ];
            resources = [
              "endpoints"
              "services"
              "pods"
              "namespaces"
            ];
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
        ];
      };
      ClusterRoleBinding.coredns = {
        roleRef = {
          apiGroup = "rbac.authorization.k8s.io";
          kind = "ClusterRole";
          name = "coredns";
        };
        subjects = [
          {
            kind = "ServiceAccount";
            name = "default";
            namespace = "kube-system";
          }
        ];
      };
    };
    kubernetes.resources.${cfg.namespace} = {
      ConfigMap.coredns = {
        data.Corefile = ''
          .:53 {
              log
              errors
              health {
                 lameduck 5s
              }
              ready
              kubernetes ${config.clusterDomain} in-addr.arpa ip6.arpa {
                 pods insecure
                 endpoint_pod_names
                 fallthrough in-addr.arpa ip6.arpa
                 ttl 30
              }
              prometheus :9153
              forward . 1.1.1.1 {
                 max_concurrent 1000
              }
              cache 30
              loop
              reload
              loadbalance
          }
        '';
      };
      Service.coredns = {
        metadata.labels = {
          "app.kubernetes.io/instance" = "coredns";
          "app.kubernetes.io/name" = "coredns";
          k8s-app = "coredns";
          "kubernetes.io/cluster-service" = "true";
          "kubernetes.io/name" = "CoreDNS";
        };
        spec = {
          clusterIP = lib.head config.clusterDNS;
          clusterIPs = config.clusterDNS;
          ipFamilyPolicy = "PreferDualStack";
          ports = [
            {
              name = "udp-53";
              port = 53;
              protocol = "UDP";
              targetPort = 53;
            }
            {
              name = "tcp-53";
              port = 53;
              protocol = "TCP";
              targetPort = 53;
            }
          ];
          selector.k8s-app = "coredns";
          type = "ClusterIP";
        };
      };
      Deployment.coredns = {
        metadata.labels.k8s-app = "coredns";
        spec = {
          inherit (cfg) replicas;
          selector.matchLabels.k8s-app = "coredns";
          strategy = {
            rollingUpdate = {
              maxSurge = "25%";
              maxUnavailable = 1;
            };
            type = "RollingUpdate";
          };
          template = {
            metadata = {
              annotations = { }; # Add some hash here
              labels.k8s-app = "coredns";
            };
            spec = {
              containers = lib.mkNamedList {
                coredns = {
                  args = [
                    "-conf"
                    "/etc/coredns/Corefile"
                  ];
                  image = "coredns/coredns:${cfg.version}";
                  imagePullPolicy = "IfNotPresent";
                  livenessProbe = {
                    failureThreshold = 5;
                    httpGet = {
                      path = "/health";
                      port = 8080;
                      scheme = "HTTP";
                    };
                    initialDelaySeconds = 60;
                    periodSeconds = 10;
                    successThreshold = 1;
                    timeoutSeconds = 5;
                  };
                  ports = lib.mkNamedList {
                    udp-53 = {
                      containerPort = 53;
                      protocol = "UDP";
                    };
                    tcp-53 = {
                      containerPort = 53;
                      protocol = "TCP";
                    };
                    tcp-9153 = {
                      containerPort = 9153;
                      protocol = "TCP";
                    };
                  };
                  readinessProbe = {
                    failureThreshold = 1;
                    httpGet = {
                      path = "/ready";
                      port = 8181;
                      scheme = "HTTP";
                    };
                    initialDelaySeconds = 30;
                    periodSeconds = 5;
                    successThreshold = 1;
                    timeoutSeconds = 5;
                  };
                  resources = {
                    limits = {
                      cpu = "100m";
                      memory = "128Mi";
                    };
                    requests = {
                      cpu = "100m";
                      memory = "128Mi";
                    };
                  };
                  securityContext = {
                    allowPrivilegeEscalation = false;
                    capabilities = {
                      add = [ "NET_BIND_SERVICE" ];
                      drop = [ "ALL" ];
                    };
                    readOnlyRootFilesystem = true;
                  };
                  volumeMounts = [
                    {
                      mountPath = "/etc/coredns";
                      name = "config-volume";
                    }
                  ];
                };
              };
              dnsPolicy = "Default";
              serviceAccountName = "default";
              terminationGracePeriodSeconds = 30;
              tolerations = [
                {
                  effect = "NoSchedule";
                  key = "node-role.kubernetes.io/control-plane";
                  operator = "Exists";
                }
              ];
              volumes = [
                {
                  configMap = {
                    items = [
                      {
                        key = "Corefile";
                        path = "Corefile";
                      }
                    ];
                    name = "coredns";
                  };
                  name = "config-volume";
                }
              ];
            };
          };
        };
      };
    };
  };
}
