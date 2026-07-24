{
  config,
  pkgs,
  pkgsOff,
  lib,
  hlib,
  ...
}:
let
  moduleName = "cheapam";
  cfg = config.${moduleName};
in
{
  options.${moduleName} = {
    enable = lib.mkEnableOption moduleName;
    crossArch.enable = lib.mkEnableOption ''
      also publishing this CSI volume's ${moduleName} build for the opposite
      (foreign) architecture via pkgsOff, for a mixed-arch cluster. pkgsOff is
      a full second nixpkgs evaluation (not real cross-compilation), which
      measurably slows every eval/deploy (~5 minutes observed) even when
      nothing on the cluster is that architecture yet -- off by default,
      enable once you actually have a foreign-arch node needing this volume
    '';
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
              "watch"
              "patch"
            ];
          in
          [
            {
              apiGroups = [ "" ];
              resources = [
                "nodes"
                "nodes/status"
                "services"
                "services/status"
              ];
              inherit verbs;
            }
            {
              apiGroups = [ "" ];
              resources = [ "configmaps" ];
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

      kube-system.ExternalSecret.hcloud-cheapam = hlib.eso.mkToken "name:hcloud-token";
      kube-system.Deployment.cheapam = {
        spec = {
          replicas = 1;
          selector.matchLabels.app = moduleName;
          template = {
            metadata.labels.app = moduleName;
            spec = {
              serviceAccountName = moduleName;
              containers = lib.mkNamedList {
                ${moduleName} = {
                  command = [ moduleName ];
                  image = "quay.io/nix-csi/scratch:1.0.1";
                  env = lib.mkNamedList {
                    PYTHONUNBUFFERED.value = "1";
                    HCLOUD_TOKEN.valueFrom.secretKeyRef = {
                      name = "hcloud-cheapam";
                      key = "token";
                    };
                  };
                  volumeMounts = [
                    {
                      name = "nix-csi";
                      mountPath = "/nix";
                      subPath = "nix";
                    }
                  ];
                };
              };
              volumes = lib.mkNamedList {
                nix-csi.csi = {
                  driver = "nixkube";
                  readOnly = true;
                  volumeAttributes = {
                    ${pkgs.stdenv.hostPlatform.system} = pkgs.cheapam;
                  }
                  // lib.optionalAttrs cfg.crossArch.enable {
                    ${pkgsOff.stdenv.hostPlatform.system} = pkgsOff.cheapam;
                  };
                };
              };
            };
          };
        };
      };
    };
  };
}
