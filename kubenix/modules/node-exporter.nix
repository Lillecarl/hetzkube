{
  config,
  pkgs,
  lib,
  ...
}:
let
  moduleName = "node-exporter";
  cfg = config.${moduleName};
in
{
  options.${moduleName} = {
    enable = lib.mkEnableOption moduleName;
    namespace = lib.mkOption {
      type = lib.types.str;
    };
  };
  config = lib.mkIf cfg.enable {
    kubernetes.resources.none.Namespace.${cfg.namespace} = { };
    kubernetes.resources.${cfg.namespace} = {
      DaemonSet.node-exporter = {
        metadata = {
          labels = {
            app = "node-exporter";
          };
        };
        spec = {
          selector = {
            matchLabels = {
              app = "node-exporter";
            };
          };
          template = {
            metadata = {
              labels = {
                app = "node-exporter";
              };
            };
            spec = {
              hostNetwork = true;
              hostPID = true;
              tolerations = [
                {
                  key = "node-role.kubernetes.io/control-plane";
                  operator = "Exists";
                  effect = "NoSchedule";
                }
              ];
              containers = [
                {
                  name = "node-exporter";
                  image = "prom/node-exporter:latest";
                  args = [
                    "--path.procfs=/host/proc"
                    "--path.sysfs=/host/sys"
                    "--path.rootfs=/host/root"
                    "--collector.systemd"
                    "--collector.processes"
                  ];
                  ports = [
                    {
                      containerPort = 9100;
                      hostPort = 9100;
                      name = "metrics";
                    }
                  ];
                  volumeMounts = [
                    {
                      name = "proc";
                      mountPath = "/host/proc";
                      readOnly = true;
                    }
                    {
                      name = "sys";
                      mountPath = "/host/sys";
                      readOnly = true;
                    }
                    {
                      name = "root";
                      mountPath = "/host/root";
                      mountPropagation = "HostToContainer";
                      readOnly = true;
                    }
                    {
                      name = "dbus";
                      mountPath = "/var/run/dbus/system_bus_socket";
                      readOnly = true;
                    }
                  ];
                }
              ];
              volumes = [
                {
                  name = "proc";
                  hostPath = {
                    path = "/proc";
                  };
                }
                {
                  name = "sys";
                  hostPath = {
                    path = "/sys";
                  };
                }
                {
                  name = "root";
                  hostPath = {
                    path = "/";
                  };
                }
                {
                  name = "dbus";
                  hostPath = {
                    path = "/var/run/dbus/system_bus_socket";
                  };
                }
              ];
            };
          };
        };
      };
      VMNodeScrape.node-exporter = {
        spec = {
          port = "9100";
          path = "/metrics";
          interval = "30s";
          relabelConfigs = [
            {
              action = "replace";
              sourceLabels = [ "__meta_kubernetes_node_name" ];
              targetLabel = "node";
            }
            {
              action = "replace";
              replacement = "node-exporter";
              targetLabel = "job";
            }
          ];
        };
      };
    };
  };
}
