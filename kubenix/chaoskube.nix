{
  config,
  lib,
  ...
}:
let
  moduleName = "chaoskube";
  cfg = config.${moduleName};
in
{
  options.${moduleName} = {
    enable = lib.mkEnableOption moduleName;
    baseName = lib.mkOption {
      type = lib.types.nonEmptyStr;
      default = moduleName;
    };
    namespace = lib.mkOption {
      type = lib.types.nonEmptyStr;
      default = moduleName;
    };
    version = lib.mkOption {
      type = lib.types.nonEmptyStr;
      default = "v0.37.0";
    };
    args = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = {
        no-dry-run = ""; # This makes things go poof
        interval = "15m";
        minimum-age = "6h";
        timezone = "Europe/Stockholm";
      };
    };
  };
  config =
    let
      fullName = "${cfg.namespace}-${cfg.baseName}";
      toChaosArgs =
        args: lib.mapAttrsToList (n: v: if lib.stringLength v > 0 then "--${n}=${v}" else "--${n}") args;
    in
    lib.mkIf cfg.enable {
      kubernetes.resources.none = {
        Namespace.${cfg.namespace} = { };
        ClusterRole.${fullName}.rules = [
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
        ClusterRoleBinding.${fullName} = {
          roleRef = {
            apiGroup = "rbac.authorization.k8s.io";
            kind = "ClusterRole";
            name = fullName;
          };
          subjects = {
            _namedlist = true;
            ${cfg.baseName} = {
              kind = "ServiceAccount";
              namespace = cfg.namespace;
            };
          };
        };
      };
      kubernetes.resources.${cfg.namespace} = {
        ServiceAccount.${cfg.baseName} = { };
        Deployment.${cfg.baseName}.spec = {
          strategy.type = "Recreate";
          replicas = 1;
          selector.matchLabels.app = cfg.baseName;
          template = {
            metadata.labels.app = cfg.baseName;
            spec = {
              serviceAccountName = cfg.baseName;
              containers = {
                _namedlist = true;
                ${cfg.baseName} = {
                  image = "ghcr.io/linki/chaoskube:${cfg.version}";
                  args = toChaosArgs cfg.args;
                };
              };
            };
          };
        };
      };
    };
}
