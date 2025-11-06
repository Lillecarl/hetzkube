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
    clusterDomain = lib.mkOption {
      type = lib.types.str;
      default = "cluster.local"; # Kubernetes stupid standard
    };
    helmAttrs = lib.mkOption {
      type = lib.types.anything;
      default = { };
    };
  };
  config = lib.mkIf cfg.enable {
    # Create coredns namespace
    kubernetes.resources.none.Namespace.${cfg.namespace} = { };
    kubernetes.resources.${cfg.namespace}.ConfigMap.coredns = {
      data.Corefile = ''
        .:53 {
            log
            errors
            health {
               lameduck 5s
            }
            ready
            kubernetes ${cfg.clusterDomain} in-addr.arpa ip6.arpa {
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
    # Create helm release
    helm.releases.${moduleName} = {
      namespace = cfg.namespace;

      chart = "${
        builtins.fetchTree {
          type = "github";
          owner = "coredns";
          repo = "helm";
          ref = "coredns-1.45.0";
        }
      }/charts/coredns";

      values = {
        service.ipFamilyPolicy = "RequireDualStack";
        service.name = "kube-dns";
        deployment.skipConfig = true;
        tolerations = [
          {
            key = "node-role.kubernetes.io/control-plane";
            operator = "Exists";
            effect = "NoSchedule";
          }
        ];
      }
      // cfg.helmAttrs;
    };
  };
}
