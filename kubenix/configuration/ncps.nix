{
  config,
  pkgs,
  lib,
  ...
}:
{
  config =
    let
      cacheSizeGB = 10;
      storagePath = "/var/lib/ncps";

      # TODO: Move to hlib/nix-csi something
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
            inherit name mountPath subPath;
            readOnly = true;
          }
        ) paths;

      ncps =
        let
          version = "0.8.0";
        in
        pkgs.ncps.overrideAttrs {
          inherit version;
          src = builtins.fetchTree {
            type = "github";
            owner = "kalbasit";
            repo = "ncps";
            ref = "v${version}";
          };
          vendorHash = "sha256-AcgC+zTS3eVsbcs0jim4zDBGc3lIjwPbdVT7/KQ9Lkc=";
          doCheck = false;
          doInstallCheck = false;
        };

      ncps-start = pkgs.writeShellApplication {
        name = "ncps-start";
        excludeShellChecks = [ "SC2154" ]; # Disable unassigned variable checking
        runtimeInputs = [ ncps ];
        text = ''
          set -x

          STORAGE_PATH=''${STORAGE_PATH:-"/var/lib/ncps"}
          mkdir --parents {"$STORAGE_PATH","$STORAGE_PATH/db"}
          export CACHE_DATABASE_URL=''${CACHE_DATABASE_URL:-"sqlite://$STORAGE_PATH/db/db.sqlite"} # before DATABASE_URL pls
          export CACHE_HOSTNAME=''${CACHE_HOSTNAME:-"ncps"}
          export CACHE_MAX_SIZE=''${CACHE_MAX_SIZE:-"${toString (cacheSizeGB - 1)}G"}
          export CACHE_SIGN_NARINFO=''${CACHE_SIGN_NARINFO:-"false"}
          export CACHE_STORAGE_LOCAL=''${CACHE_STORAGE_LOCAL:-"$STORAGE_PATH"}
          export CACHE_UPSTREAM_PUBLIC_KEYS=''${CACHE_UPSTREAM_PUBLIC_KEYS:-"cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="}
          export CACHE_UPSTREAM_URLS=''${CACHE_UPSTREAM_URLS:-"https://cache.nixos.org"}
          export DATABASE_URL="$CACHE_DATABASE_URL"
          export SERVER_ADDR=''${SERVER_ADDR:-"127.0.0.1:8501"}
          dbmate-ncps up
          ncps serve
        '';
      };

      nginx-config =
        pkgs.writeText "nginx.conf" # nginx
          ''
            events {
                worker_connections 1024;
            }

            http {
                server {
                    listen 8080;
                    listen [::]:8080;
                    server_name _;
                    
                    error_log /dev/stderr warn;
                    access_log /dev/stdout;

                    location / {
                        auth_basic "Restricted Access";
                        auth_basic_user_file ${./ncps.htpasswd};

                        proxy_pass http://127.0.0.1:8501;
                        
                        # Stream directly to ncps
                        proxy_buffering off;
                        proxy_request_buffering off;
                        client_max_body_size 0;
                        
                        # # HTTP 1.1 + keep-alive to upstream
                        # proxy_http_version 1.1;
                        # proxy_set_header Connection "";
                        
                        # # Standard headers
                        # proxy_set_header Host $host;
                        # proxy_set_header X-Real-IP $remote_addr;
                        # proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
                        # proxy_set_header X-Forwarded-Proto $scheme;
                    }
                }
            }          '';

      container-env = pkgs.buildEnv {
        name = "ncps-env";
        paths = [
          # required
          pkgs.dockerTools.caCertificates
          (pkgs.dockerTools.fakeNss.override {
            # extraPasswdLines = [ "nogroup:x:65534:65534::/var/empty:${pkgs.runtimeShell}" ];
            extraGroupLines = [ "nogroup:x:65534:" ];
          })
          # dev (some are PATH added by "script")
          pkgs.bash
          pkgs.coreutils
          pkgs.fishMinimal
        ];
      };

      labels = {
        "app.kubernetes.io/name" = "ncps";
      };
    in
    lib.mkIf (config.stage == "full") {
      kubernetes.resources.nix-csi = {
        StatefulSet.ncps = {
          spec = {
            serviceName = "ncps";
            updateStrategy.type = "RollingUpdate";
            podManagementPolicy = "Parallel";
            selector.matchLabels = labels;
            template = {
              metadata.labels = labels;
              metadata.annotations = {
                "kubectl.kubernetes.io/default-container" = "ncps";
              };
              spec = {
                nodeSelector."kubernetes.io/arch" = "amd64";
                containers = lib.mkNamedList {
                  ncps = {
                    image = "ghcr.io/lillecarl/nix-csi/scratch:1.0.1";
                    command = [
                      (lib.getExe pkgs.tini)
                      (lib.getExe ncps-start)
                    ];
                    env = lib.mkNamedList {
                      STORAGE_PATH.value = storagePath;
                      CACHE_ALLOW_DELETE_VERB.value = "true";
                      CACHE_ALLOW_PUT_VERB.value = "true";
                      CACHE_SECRET_KEY_PATH.value = "/etc/secrets/nix-key/nix_ed25519";
                      SERVER_ADDR.value = ":8591";
                    };
                    volumeMounts =
                      makeMounts "nix-store" [
                        "/nix"
                        "/etc/group"
                        "/etc/passwd"
                        "/etc/nsswitch.conf"
                        "/etc/ssl"
                        "/etc/pki"
                      ]
                      ++ [
                        {
                          name = "storage";
                          mountPath = storagePath;
                        }
                        {
                          name = "nix-key";
                          mountPath = "/etc/secrets/nix-key";
                          readOnly = true;
                        }
                      ];
                  };
                  nginx = {
                    image = "gcr.io/distroless/static:latest";
                    command = [
                      (lib.getExe pkgs.tini)
                      (lib.getExe pkgs.nginx)
                      "--"
                      "-c"
                      nginx-config
                      "-e"
                      "/dev/stderr"
                      "-g"
                      "daemon off; pid /tmp/nginx.pid;"
                    ];

                    securityContext = {
                      runAsUser = 1000;
                      runAsGroup = 1000;
                      runAsNonRoot = true;
                    };

                    ports = lib.mkNamedList {
                      http = {
                        name = "http";
                        containerPort = 8080;
                        protocol = "TCP";
                      };
                    };
                    volumeMounts =
                      makeMounts "nix-store" [
                        "/nix"
                        "/etc/group"
                        "/etc/passwd"
                        "/etc/nsswitch.conf"
                        "/etc/ssl"
                        "/etc/pki"
                      ]
                      ++ [
                        {
                          name = "storage";
                          mountPath = storagePath;
                        }
                      ];
                  };
                };
                volumes = lib.mkNamedList {
                  nix-store.csi = {
                    driver = "nixkube";
                    readOnly = true;
                    volumeAttributes.${pkgs.stdenv.hostPlatform.system} = container-env;
                  };
                  nix-key.secret = {
                    secretName = "nix-key";
                  };
                };
              };
            };
            volumeClaimTemplates = [
              {
                metadata.name = "storage";
                spec = {
                  accessModes = [ "ReadWriteOnce" ];
                  resources.requests.storage = "${toString cacheSizeGB}Gi";
                };
              }
            ];
          };
        };
        Service.ncps = {
          spec = {
            type = "ClusterIP";
            selector = labels;
            ports = lib.mkNamedList {
              http = {
                port = 80;
                targetPort = "http";
                protocol = "TCP";
              };
            };
          };
        };
      };
    };
}
