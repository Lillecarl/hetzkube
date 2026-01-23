{
  pkgs,
  lib,
  ...
}:
let
  moduleName = "cnpg-primaryswap";
in
{
  config =
    let
      swapPrimary = pkgs.writeShellApplication {
        name = "swapPrimary";
        excludeShellChecks = [ "SC1091" ]; # yolo
        runtimeInputs = [
          pkgs.kubectl-cnpg
          pkgs.jq
        ];
        text = # bash
          ''
            source ${../../scripts/cnpg-switchover.sh} pg0 database
          '';
      };
    in
    {
      kubernetes.resources.none.Namespace.database = { };
      kubernetes.resources.database = {
        CronJob.${moduleName} =
          let
            secondUtils = rec {
              minutes = count: 60 * count;
              hours = count: (minutes 60) * count;
              days = count: (hours 24) * count;
              weeks = count: (days 7) * count;
              months = count: (days 30) * count;
              years = count: (days 365) * count;
            };
          in
          {
            spec = {
              schedule = "0 4 * * *";
              concurrencyPolicy = "Forbid";
              jobTemplate.spec = {
                backoffLimit = 10;
                ttlSecondsAfterFinished = secondUtils.weeks 1;
                template = {
                  metadata.labels.app = moduleName;
                  spec = {
                    securityContext = {
                      runAsUser = 1000;
                      runAsGroup = 1000;
                      fsGroup = 1000;
                    };
                    nodeSelector."kubernetes.io/arch" = "amd64";
                    restartPolicy = "OnFailure";
                    serviceAccountName = moduleName;
                    containers = lib.mkNamedList {
                      ${moduleName} = {
                        command = [
                          (lib.getExe pkgs.tini)
                          (lib.getExe swapPrimary)
                        ];
                        image = "gcr.io/distroless/static:latest";
                        volumeMounts = [
                          {
                            name = "nix-store";
                            mountPath = "/nix";
                            subPath = "nix";
                            readOnly = true;
                          }
                        ];
                      };
                    };
                    volumes = lib.mkNamedList {
                      nix-store.csi = {
                        driver = "nix.csi.store";
                        readOnly = true;
                      };
                    };
                  };
                };
              };
            };
          };
        ServiceAccount.${moduleName} = { };
        Role.${moduleName} = {
          rules = [
            # kubectl-cnpg status: read cluster and instance information
            {
              apiGroups = [ "postgresql.cnpg.io" ];
              resources = [
                "clusters"
                "clusters/status"
              ];
              verbs = [
                "get"
                "list"
              ];
            }
            # kubectl-cnpg status: read pod status for instances
            {
              apiGroups = [ "" ];
              resources = [ "pods" ];
              verbs = [
                "get"
                "list"
              ];
            }
            # kubectl-cnpg status: read PDB status
            {
              apiGroups = [ "policy" ];
              resources = [ "poddisruptionbudgets" ];
              verbs = [
                "get"
                "list"
              ];
            }
            # kubectl-cnpg promote: update cluster to trigger switchover
            {
              apiGroups = [ "postgresql.cnpg.io" ];
              resources = [
                "clusters"
                "clusters/status"
              ];
              verbs = [
                "patch"
                "update"
              ];
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
              namespace = "database";
            }
          ];
        };
      };
    };
}
