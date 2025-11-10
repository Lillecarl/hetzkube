{
  config,
  pkgs,
  pkgsArm,
  lib,
  ...
}:
let
  moduleName = "cheapam";
  cfg = config.${moduleName};
in
{
  options.${moduleName} = {
    enable = lib.mkEnableOption moduleName;
  };
  config = lib.mkIf cfg.enable {
    kubernetes.resources = {
      kube-system.ServiceAccount.cheapam = { };
      none.ClusterRole.cheapam = {
        rules = [
          {
            apiGroups = [ "" ];
            resources = [ "nodes" ];
            verbs = [
              "get"
              "list"
              "watch"
              "patch"
            ];
          }
          {
            apiGroups = [ "" ];
            resources = [ "configmaps" ];
            verbs = [
              "get"
              "list"
              "watch"
              "create"
              "patch"
            ];
          }
          {
            apiGroups = [ "metallb.io" ];
            resources = [ "ipaddresspools" ];
            verbs = [
              "get"
              "list"
              "watch"
              "create"
              "patch"
            ];
          }
          {
            apiGroups = [ "externaldns.k8s.io" ];
            resources = [ "dnsendpoints" ];
            verbs = [
              "get"
              "list"
              "watch"
              "create"
              "patch"
            ];
          }
        ];
      };
      none.ClusterRoleBinding.cheapam = {
        roleRef = {
          apiGroup = "rbac.authorization.k8s.io";
          kind = "ClusterRole";
          name = "cheapam";
        };
        subjects = [
          {
            kind = "ServiceAccount";
            name = "cheapam";
            namespace = "kube-system";
          }
        ];
      };

      kube-system.Deployment.cheapam = {
        spec = {
          replicas = 1;
          selector.matchLabels.app = "cheapam";
          template = {
            metadata.labels.app = "cheapam";
            spec = {
              serviceAccountName = "cheapam";
              containers = [
                {
                  name = "cheapam";
                  command = [ "cheapam" ];
                  image = "quay.io/nix-csi/scratch:1.0.0";
                  env = {
                    _namedlist = true;
                    PATH.value = "/nix/var/result/bin";
                    PYTHONUNBUFFERED.value = "1";
                  };
                  volumeMounts = [
                    {
                      name = "nix-csi";
                      mountPath = "/nix";
                    }
                  ];
                }
              ];
              volumes = [
                {
                  name = "nix-csi";
                  csi = {
                    driver = "nix.csi.store";
                    readOnly = true;
                    volumeAttributes.${pkgs.system} = pkgs.callPackage ../cheapam { };
                    volumeAttributes.${pkgsArm.system} = pkgsArm.callPackage ../cheapam { };
                  };
                }
              ];
            };
          };
        };
      };
    };
  };
}
