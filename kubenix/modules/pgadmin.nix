{
  config,
  pkgs,
  pkgsArm,
  lib,
  ...
}:
let
  moduleName = "pgadmin";
  cfg = config.${moduleName};
in
{
  options.${moduleName} = {
    enable = lib.mkEnableOption moduleName;
    hostname = lib.mkOption {
      type = lib.types.str;
    };
    namespace = lib.mkOption {
      type = lib.types.str;
      default = moduleName;
    };
  };
  config = lib.mkIf cfg.enable {
    kubernetes.resources.none.Namespace.${cfg.namespace} = { };

    kubernetes.resources.${cfg.namespace} = {
      Secret.initpass.stringData.pass = "{{ lillepass }}";

      Deployment.${moduleName} = {
        spec = {
          replicas = 1;
          selector.matchLabels.app = moduleName;
          template = {
            metadata.labels.app = moduleName;
            spec = {
              containers = [
                {
                  name = moduleName;
                  command = [ "pgadmin-launcher" ];
                  image = "quay.io/nix-csi/scratch:1.0.1";
                  env = {
                    _namedlist = true;
                    PYTHONUNBUFFERED.value = "1";
                    INITIAL_EMAIL.value = "admin@lillecarl.com";
                    INITIAL_PASSWORD.valueFrom.secretKeyRef = {
                      name = "initpass";
                      key = "pass";
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
                    volumeAttributes.${pkgs.system} = pkgs.pgadmin-launcher;
                    # volumeAttributes.${pkgsArm.system} = pkgsArm.pgadmin-launcher;
                  };
                }
              ];
            };
          };
        };
      };
      Ingress.${moduleName} = {
        metadata.annotations = {
          "cert-manager.io/cluster-issuer" = "le-prod";
          "external-dns.alpha.kubernetes.io/ttl" = "60";
        };
        spec = {
          tls = [
            {
              hosts = [ cfg.hostname ];
              secretName = "cert";
            }
          ];
          rules = [
            {
              host = cfg.hostname;
              http = {
                paths = [
                  {
                    path = "/";
                    pathType = "Prefix";
                    backend = {
                      service = {
                        name = moduleName;
                        port = {
                          name = "http";
                        };
                      };
                    };
                  }
                ];
              };
            }
          ];
        };
      };
      Service.${moduleName} = {
        metadata.labels.app = moduleName;
        spec = {
          ports = [
            {
              protocol = "TCP";
              port = 8080;
              targetPort = 5050;
              name = "http";
            }
          ];
          selector.app = moduleName;
          type = "ClusterIP";
        };
      };
    };
  };
}
