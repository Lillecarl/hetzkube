{
  config,
  lib,
  hlib,
  ...
}:
let
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
        resources = [
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
    let
      subCfg = config;
    in
    {
      options = {
        enable = lib.mkEnableOption "external-dns instance" // {
          default = true;
        };

        namespace = lib.mkOption {
          type = lib.types.str;
          default = name;
          description = "Namespace to deploy into. If kube-system, uses ClusterRole.";
        };

        clusterScope = lib.mkEnableOption "cluster scoped permissions";

        version = lib.mkOption {
          type = lib.types.str;
          default = cfg.version;
        };

        args = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = "Arguments passed to the external-dns container.";
        };

        env = lib.mkOption {
          type = lib.types.listOf lib.types.attrs;
          default = [ ];
          description = "Environment variables for the container.";
        };

        objects = lib.mkOption {
          type = lib.types.attrs;
          description = "Generated Kubernetes objects for this instance.";
        };
      };

      config = {
        clusterScope = lib.mkDefault (subCfg.namespace == "kube-system");
        objects =
          let
            identifier = "external-dns-${name}";

            rbac =
              let
                roleNs = if subCfg.clusterScope then "none" else subCfg.namespace;
                roleType = if subCfg.clusterScope then "ClusterRole" else "Role";
                bindType = if subCfg.clusterScope then "ClusterRoleBinding" else "RoleBinding";
              in
              {
                ${roleNs} = {
                  ${roleType}.${identifier} = {
                    rules = mkRules subCfg.clusterScope;
                  };
                  ${bindType}.${identifier} = {
                    roleRef = {
                      apiGroup = "rbac.authorization.k8s.io";
                      kind = roleType;
                      name = identifier;
                    };
                    subjects = [
                      {
                        kind = "ServiceAccount";
                        name = identifier;
                        namespace = subCfg.namespace;
                      }
                    ];
                  };
                };
              };

            deployment = {
              ${config.namespace} = {
                ServiceAccount.${identifier} = { };
                Deployment."external-dns-${name}" = {
                  spec = {
                    strategy.type = "Recreate";
                    selector.matchLabels.app = "external-dns-${name}";
                    template = {
                      metadata.labels.app = "external-dns-${name}";
                      spec = {
                        serviceAccountName = identifier;
                        containers = lib.mkNamedList {
                          external-dns = {
                            image = "registry.k8s.io/external-dns/external-dns:v${subCfg.version}";
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
  options.${moduleName} = {
    enable = lib.mkEnableOption "external-dns";
    version = lib.mkOption {
      type = lib.types.str;
      default = "0.21.0";
    };
    instances = lib.mkOption {
      default = { };
      type = lib.types.attrsOf (lib.types.submodule externalDnsSubmodule);
    };
  };

  config = lib.mkIf cfg.enable {
    importyaml.${moduleName}.src =
      "https://raw.githubusercontent.com/kubernetes-sigs/external-dns/v${cfg.version}/config/crd/standard/dnsendpoints.externaldns.k8s.io.yaml";

    kubernetes = {
      apiMappings.DNSEndpoint = "externaldns.k8s.io/v1alpha1";
      namespacedMappings.DNSEndpoint = true;

      objects = lib.pipe cfg.instances [
        (lib.mapAttrsToList (_: instance: instance))
        (lib.filter (instance: instance.enable))
        (lib.map (instance: instance.objects))
        lib.mkMerge
      ];
    };
  };
}
