{
  config,
  pkgs,
  pkgsOff,
  lib,
  hlib,
  ...
}:
{
  config =
    let
      mkEnv =
        pkgs:
        let
          script = pkgs.writeShellApplication {
            name = "cifsmounter";
            excludeShellChecks = [ "SC2154" ]; # Disable unassigned variable checking
            runtimeInputs = [
              pkgs.cifs-utils
              pkgs.coreutils
              pkgs.util-linuxMinimal
            ];
            text = ''
              mountpath=/var/lib/cifs/mount
              while :; do
                if ! findmnt --mountpoint "$mountpath"; then
                mkdir --parents "$mountpath"
                echo Mounting
                mount -t cifs \
                  -o mfsymlinks \
                  -o cache=strict \
                  -o noserverino \
                  -o username="$username" \
                  -o password="$password" \
                  "$server_addr" \
                  "$mountpath"
                fi
                echo Sleeping
                sleep 30
              done
            '';
          };
        in
        pkgs.buildEnv {
          name = "cifsmounter-env";
          paths = [
            # required
            pkgs.dockerTools.caCertificates
            pkgs.dockerTools.fakeNss
            pkgs.tini
            script
            # dev (some are PATH added by "script")
            pkgs.bash
            pkgs.cifs-utils
            pkgs.coreutils
            pkgs.fishMinimal
            pkgs.iputils
            pkgs.util-linuxMinimal
          ];
        };

      labels = {
        "app.kubernetes.io/name" = "cifsmounter";
      };
    in
    lib.mkIf (config.stage == "full") {
      nix-csi.push = true;
      kubernetes.resources.kube-system = {
        ExternalSecret.sb1-kube = hlib.eso.mkBasic "name:hcloud-sb1-kube";
        DaemonSet.cifsmounter = {
          spec = {
            updateStrategy = {
              type = "RollingUpdate";
              rollingUpdate.maxUnavailable = 1;
            };
            selector.matchLabels = labels;
            template = {
              metadata.labels = labels;
              metadata.annotations = {
                "kubectl.kubernetes.io/default-container" = "cifsmounter";
              };
              spec = {
                priorityClassName = "system-node-critical";
                containers = lib.mkNamedList {
                  cifsmounter = {
                    image = "ghcr.io/lillecarl/nix-csi/scratch:1.0.1";
                    command = [
                      "tini"
                      # "cifsmounter"
                      "sleep"
                      "infinity"
                    ];
                    envFrom = [
                      {
                        secretRef = {
                          name = "sb1-kube";
                        };
                      }
                    ];
                    env = lib.mkNamedList {
                      server_addr.value = "//u531666-sub1.your-storagebox.de/531666-sub1";
                      test_file.value = pkgs.writeText "test_file" "test_content";
                    };
                    securityContext.privileged = true;
                    volumeMounts =
                      let
                        makeMounts =
                          name: paths:
                          lib.map (
                            inPath:
                            let
                              noSuffix = if lib.hasSuffix "/" inPath then lib.removeSuffix "/" inPath else inPath;
                              mountPath = if lib.hasPrefix "/" noSuffix then noSuffix else "/${noSuffix}";
                              subPath = lib.removePrefix "/" mountPath;
                            in
                            {
                              name = name;
                              inherit mountPath subPath;
                              readOnly = true;
                            }
                          ) paths;
                      in
                      makeMounts "nix-store" [
                        "/nix"
                        "/bin"
                        "/sbin"
                        "/etc/group"
                        "/etc/passwd"
                        "/etc/nsswitch.conf"
                        "/etc/ssl"
                        "/etc/pki"
                      ]
                      ++ [
                        {
                          name = "cifs";
                          mountPath = "/var/lib/cifs";
                        }
                      ];
                  };
                };
                volumes = lib.mkNamedList {
                  nix-store.csi = {
                    driver = "nix.csi.store";
                    readOnly = true;
                    volumeAttributes.${pkgs.stdenv.hostPlatform.system} = mkEnv pkgs;
                    volumeAttributes.${pkgsOff.stdenv.hostPlatform.system} = mkEnv pkgsOff;
                  };
                  cifs.hostPath = {
                    path = "/var/lib/cifs";
                    type = "DirectoryOrCreate";
                  };
                };
              };
            };
          };
        };
      };
    };
}
