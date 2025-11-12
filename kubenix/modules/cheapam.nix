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
      kube-system.ServiceAccount.${moduleName} = { };
      none.ClusterRole.${moduleName} = {
        rules =
          let
            verbs = [
              "get"
              "list"
              "create"
              "patch"
            ];
          in
          [
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
              inherit verbs;
            }
            {
              apiGroups = [ "metallb.io" ];
              resources = [ "ipaddresspools" ];
              inherit verbs;
            }
            {
              apiGroups = [ "externaldns.k8s.io" ];
              resources = [ "dnsendpoints" ];
              inherit verbs;
            }
          ];
      };
      none.ClusterRoleBinding.${moduleName} = {
        roleRef = {
          apiGroup = "rbac.authorization.k8s.io";
          kind = "ClusterRole";
          name = moduleName;
        };
        subjects = [
          {
            kind = "ServiceAccount";
            name = moduleName;
            namespace = "kube-system";
          }
        ];
      };

      kube-system.Deployment.cheapam = {
        spec = {
          replicas = 1;
          selector.matchLabels.app = moduleName;
          template = {
            metadata.labels.app = moduleName;
            spec = {
              serviceAccountName = moduleName;
              containers = [
                {
                  name = moduleName;
                  command = [ moduleName ];
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
                    volumeAttributes.${pkgs.system} = pkgs.callPackage ../../cheapam { };
                    volumeAttributes.${pkgsArm.system} = pkgsArm.callPackage ../../cheapam { };
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
