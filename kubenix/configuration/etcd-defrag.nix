{
  pkgs,
  lib,
  ...
}:
let
  moduleName = "etcd-defrag";
  defragScript = pkgs.writeShellApplication {
    name = moduleName;
    runtimeInputs = [ pkgs.kubectl ];
    text = # bash
      ''
        pod=$(kubectl get pods -n kube-system -l component=etcd -o jsonpath='{.items[0].metadata.name}')
        echo "Defragmenting etcd cluster via pod: $pod"
        kubectl exec -n kube-system "$pod" -- etcdctl defrag \
          --cluster \
          --endpoints=https://127.0.0.1:2379 \
          --cert=/etc/kubernetes/pki/etcd/server.crt \
          --key=/etc/kubernetes/pki/etcd/server.key \
          --cacert=/etc/kubernetes/pki/etcd/ca.crt
      '';
  };
in
{
  config = {
    kubernetes.resources.kube-system = {
      ServiceAccount.${moduleName} = { };
      Role.${moduleName} = {
        rules = [
          {
            apiGroups = [ "" ];
            resources = [ "pods" ];
            verbs = [
              "get"
              "list"
            ];
          }
          {
            apiGroups = [ "" ];
            resources = [ "pods/exec" ];
            verbs = [ "create" ];
          }
        ];
      };
      RoleBinding.${moduleName} = {
        roleRef = {
          apiGroup = "rbac.authorization.k8s.io";
          kind = "Role";
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
      CronJob.${moduleName} = {
        spec = {
          schedule = "0 3 * * *";
          concurrencyPolicy = "Forbid";
          jobTemplate.spec = {
            backoffLimit = 3;
            ttlSecondsAfterFinished = 604800; # 1 week
            template = {
              metadata.labels.app = moduleName;
              spec = {
                restartPolicy = "OnFailure";
                serviceAccountName = moduleName;
                containers = lib.mkNamedList {
                  ${moduleName} = {
                    command = [
                      (lib.getExe pkgs.tini)
                      "--"
                      (lib.getExe defragScript)
                    ];
                    image = "ghcr.io/lillecarl/nix-csi/scratch:1.0.1";
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
