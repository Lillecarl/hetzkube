{
  config,
  pkgs,
  pkgsOff,
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
    copyDerivations = [
      pkgs.cheapam
      pkgsOff.cheapam
    ];
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
              ];
              inherit verbs;
            }
            {
              apiGroups = [ "" ];
              resources = [ "configmaps" ];
              inherit verbs;
            }
            {
              apiGroups = [ "cilium.io" ];
              resources = [ "ciliumloadbalancerippools" ];
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

      # kube-system.Secret.hcloud-cheapam.stringData.token = "{{ hctoken }}";
      kube-system.BitwardenSecret.hcloud-cheapam = {
        spec = {
          organizationId = "a5c85a84-042e-44b8-a07e-b16f00119301";
          secretName = "hcloud-cheapam";
          map = [
            {
              bwSecretId = "4a2e1d5f-f44a-4034-afe1-b3b100adf118";
              secretKeyName = "token";
            }
          ];
          authToken = {
            secretName = "bw-auth-token";
            secretKey = "token";
          };
        };
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
                  env = lib.mkNamedList {
                    PATH.value = "/nix/var/result/bin";
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
                    volumeAttributes.${pkgs.stdenv.hostPlatform.system} = pkgs.cheapam;
                    volumeAttributes.${pkgsOff.stdenv.hostPlatform.system} = pkgsOff.cheapam;
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
