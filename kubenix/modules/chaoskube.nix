{
  config,
  lib,
  ...
}:
let
  topConfig = config;
  moduleName = "chaoskube";
  toChaosArgs =
    args: lib.mapAttrsToList (n: v: if lib.stringLength v > 0 then "--${n}=${v}" else "--${n}") args;
in
{
  options.${moduleName} = lib.mkOption {
    type = lib.types.attrsOf (
      lib.types.submodule (
        { name, config, ... }:
        {
          options = {
            enable = lib.mkEnableOption "chaoskube ${name}";
            name = lib.mkOption {
              type = lib.types.nonEmptyStr;
              default = name;
              internal = true;
            };
            namespace = lib.mkOption {
              type = lib.types.nonEmptyStr;
              default = "kube-system";
            };
            labels = lib.mkOption {
              type = lib.types.attrsOf lib.types.str;
              default = { };
            };
            annotations = lib.mkOption {
              type = lib.types.attrsOf lib.types.str;
              default = { };
            };
            version = lib.mkOption {
              type = lib.types.nonEmptyStr;
              default = "v0.37.0";
            };
            vpa = lib.mkOption {
              type = lib.types.bool;
              default = topConfig.vertical-pod-autoscaler.enable;
            };
            args = lib.mkOption {
              type = lib.types.attrsOf lib.types.str;
              description = "Arguments to pass to chaoskube, see https://github.com/linki/chaoskube?tab=readme-ov-file#flags";
            };
            # This will be consumed into the global configuration space
            kubernetes = lib.mkOption {
              type = lib.types.anything;
              internal = true;
              default = { };
            };
          };
          config =
            let
              clusterResourceName = "${moduleName}-${config.name}";
            in
            lib.mkIf config.enable {
              kubernetes.resources.none = {
                Namespace.${config.namespace} = { };

                ClusterRole.${clusterResourceName}.rules = [
                  {
                    apiGroups = [ "" ];
                    resources = [ "pods" ];
                    verbs = [
                      "list"
                      "delete"
                    ];
                  }
                  {
                    apiGroups = [ "" ];
                    resources = [ "events" ];
                    verbs = [ "create" ];
                  }
                ];

                ClusterRoleBinding.${clusterResourceName} = {
                  roleRef = {
                    apiGroup = "rbac.authorization.k8s.io";
                    kind = "ClusterRole";
                    name = clusterResourceName;
                  };
                  subjects = [
                    {
                      kind = "ServiceAccount";
                      name = config.name;
                      namespace = config.namespace;
                    }
                  ];
                };
              };

              kubernetes.resources.${config.namespace} = {
                ServiceAccount.${config.name} = { };
                Deployment.${config.name}.spec = {
                  strategy.type = "Recreate";
                  replicas = 1;
                  selector.matchLabels.app = config.name;
                  template = {
                    metadata = {
                      labels = lib.recursiveUpdate {
                        app = config.name;
                      } config.labels;
                      inherit (config) annotations;
                    };
                    spec = {
                      serviceAccountName = config.name;
                      containers = lib.mkNamedList {
                        ${config.name} = {
                          image = "ghcr.io/linki/chaoskube:${config.version}";
                          args = toChaosArgs config.args;
                        };
                      };
                    };
                  };
                };

                VerticalPodAutoscaler.chaoskube = lib.mkIf config.vpa {
                  spec.targetRef = {
                    apiVersion = "apps/v1";
                    kind = "Deployment";
                    name = config.name;
                  };

                  # Automatically evicts and resizes pods
                  spec.updatePolicy.updateMode = "InPlaceOrRecreate";

                  # Optional: Prevent VPA from requesting too little or too much
                  # spec.resourcePolicy.containerPolicies = [
                  #   {
                  #     containerName = "*";
                  #     minAllowed.cpu = "10m";
                  #     minAllowed.memory = "15Mi";
                  #   }
                  # ];
                };
              };
            };
        }
      )
    );
    default = { };
    description = "Chaoskube instances";
  };

  config.kubernetes = lib.mkMerge (
    lib.pipe config.${moduleName} [
      lib.attrValues
      (lib.map (v: v.kubernetes))
    ]
  );
}
