{
  config,
  lib,
  hlib,
  ...
}:
let
  rootConfig = config;
  moduleName = "external-dns";
  cfg = config.${moduleName};

  mkRules =
    isClusterScope:
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
        resources =
          [
            "services"
            "pods"
          ]
          ++ lib.optionals isClusterScope [
            "nodes"
            "namespaces"
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
        apiGroups = [ "gateway.networking.k8s.io" ];
        resources = [
          "gateways"
          "httproutes"
        ];
        inherit verbs;
      }
    ];

  externalDnsSubmodule =
    { name, config, ... }:
    {
      options = {
        enable = lib.mkEnableOption "external-dns instance";

        namespace = lib.mkOption {
          type = lib.types.str;
          default = name;
          description = "Namespace to deploy into. If kube-system, uses ClusterRole.";
        };

        version = lib.mkOption {
          type = lib.types.str;
          default = "0.20.0";
        };

        image = lib.mkOption {
          type = lib.types.str;
          default = "registry.k8s.io/external-dns/external-dns:v${config.version}";
        };

        secretName = lib.mkOption {
          type = lib.types.str;
          default = "cloudflare";
          description = "Name of the secret containing the API token";
        };

        args = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [
            "--source=crd"
            "--source=gateway-httproute"
            "--source=ingress"
            "--source=service"
            "--provider=cloudflare"
            "--txt-owner-id=${rootConfig.clusterName}"
          ];
          description = "Arguments passed to the external-dns container.";
        };

        env = lib.mkOption {
          type = lib.types.listOf lib.types.attrs;
          default = [
            {
              name = "CF_API_TOKEN";
              valueFrom = {
                secretKeyRef = {
                  name = config.secretName;
                  key = "token";
                };
              };
            }
          ];
          description = "Environment variables for the container.";
        };

        kubernetes.resources = lib.mkOption {
          type = lib.types.attrs;
          description = "Generated Kubernetes resources for this instance.";
        };
      };

      config = {
        kubernetes.resources =
          let
            isGlobal = config.namespace == "kube-system";
            roleName = "external-dns-${name}";
            saName = "external-dns-${name}";

            rbac =
              if isGlobal then
                {
                  ClusterRole.${roleName} = {
                    rules = mkRules true;
                  };
                  ClusterRoleBinding.${roleName} = {
                    roleRef = {
                      apiGroup = "rbac.authorization.k8s.io";
                      kind = "ClusterRole";
                      name = roleName;
                    };
                    subjects = [
                      {
                        kind = "ServiceAccount";
                        name = saName;
                        namespace = config.namespace;
                      }
                    ];
                  };
                }
              else
                {
                  resources.${config.namespace} = {
                    Role.${roleName} = {
                      rules = mkRules false;
                    };
                    RoleBinding.${roleName} = {
                      roleRef = {
                        apiGroup = "rbac.authorization.k8s.io";
                        kind = "Role";
                        name = roleName;
                      };
                      subjects = [
                        {
                          kind = "ServiceAccount";
                          name = saName;
                          namespace = config.namespace;
                        }
                      ];
                    };
                  };
                };

            deployment = {
              resources.${config.namespace} = {
                ServiceAccount.${saName} = { };
                ExternalSecret.${config.secretName} = hlib.eso.mkToken "name:cloudflare-token";
                Deployment."external-dns-${name}" = {
                  spec = {
                    strategy.type = "Recreate";
                    selector.matchLabels.app = "external-dns-${name}";
                    template = {
                      metadata.labels.app = "external-dns-${name}";
                      spec = {
                        serviceAccountName = saName;
                        containers = lib.mkNamedList {
                          external-dns = {
                            image = config.image;
                            inherit (config) args env;
                          };
                        };
                      };
                    };
                  };
                };
              };
            };
          in
          lib.mkMerge [
            rbac
            deployment
          ];
      };
    };
in
{
  options.${moduleName} = lib.mkOption {
    default = { };
    type = lib.types.attrsOf (lib.types.submodule externalDnsSubmodule);
  };

  config = lib.mkIf (cfg != { }) {
    # We assume all instances use the same CRD version, or at least compatible ones.
    # We pick the version from the first enabled instance or default to 0.20.0 if none enabled (though config is mkIf cfg != {})
    importyaml.${moduleName} =
      let
        # Fallback version if needed, though cfg is not empty here
        version =
          if (lib.attrNames cfg) != [ ] then
            (lib.head (lib.attrValues cfg)).version
          else
            "0.20.0";
      in
      {
        src = "https://raw.githubusercontent.com/kubernetes-sigs/external-dns/v${version}/config/crd/standard/dnsendpoints.externaldns.k8s.io.yaml";
      };

    kubernetes = {
      apiMappings = {
        DNSEndpoint = "externaldns.k8s.io/v1alpha1";
      };
      resources = lib.mkMerge (
        lib.mapAttrsToList (n: v: v.kubernetes.resources) (lib.filterAttrs (n: v: v.enable) cfg)
      );
    };
  };
}
