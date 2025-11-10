{
  config,
  lib,
  ...
}:
let
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
              default = "chaoskube";
            };
            version = lib.mkOption {
              type = lib.types.nonEmptyStr;
              default = "v0.37.0";
            };
            args = lib.mkOption {
              type = lib.types.attrsOf lib.types.str;
              description = "Arguments to pass to chaoskube, see https://github.com/linki/chaoskube?tab=readme-ov-file#flags";
            };
            # This will be consumed into the global configuration namespace
            kubernetes = lib.mkOption {
              type = lib.types.anything;
              internal = true;
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
                    metadata.labels.app = config.name;
                    spec = {
                      serviceAccountName = config.name;
                      containers = {
                        _namedlist = true;
                        ${config.name} = {
                          image = "ghcr.io/linki/chaoskube:${config.version}";
                          args = toChaosArgs config.args;
                        };
                      };
                    };
                  };
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
