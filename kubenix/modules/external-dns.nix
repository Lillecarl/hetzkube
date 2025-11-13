{
  config,
  lib,
  ...
}:
let
  moduleName = "external-dns";
  cfg = config.${moduleName};
in
{
  options.${moduleName} = {
    enable = lib.mkEnableOption moduleName;
    namespace = lib.mkOption {
      type = lib.types.str;
      default = "external-dns";
    };
    version = lib.mkOption {
      type = lib.types.str;
      default = "0.19.0";
    };
  };
  config = lib.mkIf cfg.enable {
    importyaml.${moduleName} = {
      src = "https://raw.githubusercontent.com/kubernetes-sigs/external-dns/v${cfg.version}/config/crd/standard/dnsendpoints.externaldns.k8s.io.yaml";
    };
    kubernetes = {
      resources.none = {
        Namespace.${cfg.namespace} = { };
        ClusterRole.external-dns = {
          rules = [
            {
              apiGroups = [ "" ];
              resources = [
                "services"
                "pods"
              ];
              verbs = [
                "get"
                "watch"
                "list"
              ];
            }
            {
              apiGroups = [ "discovery.k8s.io" ];
              resources = [ "endpointslices" ];
              verbs = [
                "get"
                "watch"
                "list"
              ];
            }
            {
              apiGroups = [
                "extensions"
                "networking.k8s.io"
              ];
              resources = [ "ingresses" ];
              verbs = [
                "get"
                "watch"
                "list"
              ];
            }
            {
              apiGroups = [ "" ];
              resources = [ "nodes" ];
              verbs = [
                "list"
                "watch"
              ];
            }
            {
              apiGroups = [ "externaldns.k8s.io" ];
              resources = [ "dnsendpoints" ];
              verbs = [
                "get"
                "watch"
                "list"
              ];
            }
            {
              apiGroups = [ "externaldns.k8s.io" ];
              resources = [ "dnsendpoints/status" ];
              verbs = [ "*" ];
            }
          ];
        };
        ClusterRoleBinding.external-dns-viewer = {
          roleRef = {
            apiGroup = "rbac.authorization.k8s.io";
            kind = "ClusterRole";
            name = "external-dns";
          };
          subjects = [
            {
              kind = "ServiceAccount";
              name = "external-dns";
              namespace = cfg.namespace;
            }
          ];
        };
      };
      resources.${cfg.namespace} = {
        ServiceAccount.external-dns = { };
        Secret.cloudflare.stringData.token = "{{ cftoken }}";
        Deployment.external-dns = {
          spec = {
            strategy.type = "Recreate";
            selector.matchLabels.app = "external-dns";
            template = {
              metadata.labels.app = "external-dns";
              spec = {
                serviceAccountName = "external-dns";
                containers = {
                  _namedlist = true;
                  external-dns = {
                    image = "registry.k8s.io/external-dns/external-dns:v${cfg.version}";
                    args = [
                      "--source=service"
                      "--source=crd"
                      "--source=ingress"
                      "--provider=cloudflare"
                      "--txt-owner-id=${config.clusterName}"
                    ];
                    env = [
                      {
                        name = "CF_API_TOKEN";
                        valueFrom = {
                          secretKeyRef = {
                            name = "cloudflare";
                            key = "token";
                          };
                        };
                      }
                    ];
                  };
                };
              };
            };
          };
        };
      };
      apiMappings = {
        DNSEndpoint = "externaldns.k8s.io/v1alpha1";
      };
    };
  };
}
