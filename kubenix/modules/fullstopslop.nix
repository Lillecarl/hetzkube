{
  config,
  pkgs,
  pkgsOff,
  lib,
  eso,
  ...
}:
let
  moduleName = "fullstopslop";
  cfg = config.${moduleName};
in
{
  options.${moduleName} = {
    enable = lib.mkEnableOption moduleName;
  };
  config =
    let
      mkFakeNss =
        {
          users ? [ 1000 ],
          groups ? [ 1000 ],
        }:
        pkgs.dockerTools.fakeNss.override {
          extraPasswdLines = lib.map (uid: "${uid}:x:${uid}:${uid}::/home/${uid}:${pkgs.runtimeShell}") users;
          extraGroupLines = lib.map (gid: "${gid}:x:${gid}:") groups;
        };

      root = pkgs.writeShellApplication {
        name = "init";
        runtimeInputs = [
          pkgs.rsync
          pkgs.coreutils
        ];
        text = # bash
          ''
            rsync --archive ${pkgs.dockerTools.binSh}/ /
            rsync --archive ${pkgs.dockerTools.caCertificates}/ /
            rsync --archive ${pkgs.dockerTools.usrBinEnv}/ /
            rsync --archive ${mkFakeNss { }}/ /
            mkdir --parents "$HOME"
            chown --recursive 1000:1000 "$HOME"

          '';
      };
      user = pkgs.writeShellApplication {
        name = "init";
        runtimeInputs = [
          pkgs.claude-code
          pkgs.git
          pkgs.kubectl
          pkgs.coreutils
        ];
        text = # bash
          ''
            set -x
            cd "$HOME"
            # cp /var/run/secrets/claude/.claude.json "$HOME/.claude.json"
            rm --recursive --force fullstopslop "$HOME/error"
            set +x
            echo git clone
            git clone "https://lillecarl:$GH_PAT@github.com/lillecarl/fullstopslop.git"
            set -x
            cd fullstopslop
            git config user.name "AICarl"
            git config user.email "github@lillecarl.com"
            INIT_SLEEP="''${INIT_SLEEP:-""}"
            if test -n "$INIT_SLEEP"; then
              echo "Sleeping for $INIT_SLEEP"
              sleep "$INIT_SLEEP"
            fi
            cat README.md | claude --print --dangerously-skip-permissions --model haiku
            if test -f "$HOME/error"; then
              sleep 300
              exit 1
            fi
          '';
      };
      run = pkgs.writeShellApplication {
        name = "run";
        runtimeInputs = [
          pkgs.util-linux
        ];
        text = # bash
          ''
            set -x
            export SHELL=${pkgs.runtimeShell}
            ${lib.getExe root}
            exec setpriv \
              --clear-groups \
              --reuid=1000 \
              --regid=1000 \
              --inh-caps=-all \
              ${lib.getExe user}
          '';
      };
      env = pkgs.buildEnv {
        name = moduleName;
        paths = [
          pkgs.bash # Used when logging into CC first time
          pkgs.tini
          run
        ];
      };
    in
    lib.mkIf cfg.enable {
      kubernetes.resources.none.Namespace.${moduleName} = { };
      kubernetes.resources.${moduleName} = {
        ExternalSecret.github-pat = eso.mkToken "name:github-fullstopslop";
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
              schedule = "0 */5 * * 1-5";
              jobTemplate.spec = {
                backoffLimit = 10;
                ttlSecondsAfterFinished = secondUtils.weeks 1;
                concurrencyPolicy = "Forbid";
                template = {
                  metadata.labels.app = moduleName;
                  spec = {
                    restartPolicy = "OnFailure";
                    serviceAccountName = moduleName;
                    containers = lib.mkNamedList {
                      ${moduleName} = {
                        command = [
                          "tini"
                          "run"
                        ];
                        image = "quay.io/nix-csi/scratch:1.0.1";
                        env = lib.mkNamedList {
                          # INIT_SLEEP.value = "600";
                          GH_PAT.valueFrom.secretKeyRef = {
                            name = "github-pat";
                            key = "token";
                          };
                        };
                        volumeMounts = lib.mkNamedList {
                          nix-csi.mountPath = "/nix";
                          home.mountPath = "/home/1000";
                          # claude-secret = {
                          #   mountPath = "/var/run/secrets/claude";
                          #   readOnly = true;
                          # };
                        };
                      };
                    };
                    volumes = lib.mkNamedList {
                      nix-csi.csi = {
                        driver = "nix.csi.store";
                        readOnly = true;
                        volumeAttributes.${pkgs.stdenv.hostPlatform.system} = env;
                      };
                      claude-secret.secret.secretName = "claude";
                      home.persistentVolumeClaim.claimName = "${moduleName}-home";
                    };
                  };
                };
              };
            };
          };
        PersistentVolumeClaim."${moduleName}-home" = {
          spec = {
            accessModes = [ "ReadWriteOnce" ];
            storageClassName = "hcloud-volumes";
            resources.requests.storage = "10Gi";
          };
        };
        ServiceAccount.${moduleName} = { };
        Role.${moduleName} = {
          rules = [
            {
              apiGroups = [ "" ];
              resources = [ "secrets" ];
              verbs = [
                "get"
                "list"
                "watch"
                "create"
                "update"
                "patch"
                "delete"
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
              namespace = moduleName;
            }
          ];
        };
      };
    };
}
