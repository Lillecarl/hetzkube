{
  config,
  lib,
  hlib,
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
      default = "0.20.0";
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
          rules =
            let
              verbs = [
                "get"
                "list"
                "watch"
              ];
            in
            [
              {
                apiGroups = [ "" ];
                resources = [
                  "services"
                  "pods"
                ];
                inherit verbs;
              }
              {
                apiGroups = [ "discovery.k8s.io" ];
                resources = [ "endpointslices" ];
                inherit verbs;
              }
              {
                apiGroups = [ "networking.k8s.io" ];
                resources = [ "ingresses" ];
                inherit verbs;
              }
              {
                apiGroups = [ "" ];
                resources = [ "nodes" ];
                inherit verbs;
              }
              {
                apiGroups = [ "externaldns.k8s.io" ];
                resources = [ "dnsendpoints" ];
                inherit verbs;
              }
              {
                apiGroups = [ "externaldns.k8s.io" ];
                resources = [ "dnsendpoints/status" ];
                verbs = [ "*" ];
              }
              {
                apiGroups = [ "" ];
                resources = [ "namespaces" ];
                inherit verbs;
              }
              {
                apiGroups = [ "gateway.networking.k8s.io" ];
                resources = [
                  "gateways"
                  "httproutes"
                ];
                inherit verbs;
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
        ExternalSecret.cloudflare = hlib.eso.mkToken "name:cloudflare-token";
        Deployment.external-dns = {
          spec = {
            strategy.type = "Recreate";
            selector.matchLabels.app = "external-dns";
            template = {
              metadata.labels.app = "external-dns";
              spec = {
                serviceAccountName = "external-dns";
                containers = lib.mkNamedList {
                  external-dns = {
                    image = "registry.k8s.io/external-dns/external-dns:v${cfg.version}";
                    args = [
                      "--source=crd"
                      "--source=gateway-httproute"
                      "--source=ingress"
                      "--source=service"
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
