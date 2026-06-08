{
  config,
  lib,
  hlib,
  ...
}:
let
  moduleName = "cnpg";
  cfg = config.${moduleName};
in
{
  options.${moduleName} = {
    enable = lib.mkEnableOption moduleName;
    url = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = "https://raw.githubusercontent.com/cloudnative-pg/cloudnative-pg/release-1.29/releases/cnpg-1.29.1.yaml";
    };
  };
  config = lib.mkIf cfg.enable {
    importyaml.${moduleName} = {
      src = cfg.url;
    };
    kubernetes = {
      resources.none.Namespace.database = { };
      resources.cnpg-system.VMPodScrape.cnpg-operator = {
        spec = {
          podMetricsEndpoints = [
            {
              port = "metrics";
              path = "/metrics";
              interval = "30s";
            }
          ];
          selector = {
            matchLabels = {
              "app.kubernetes.io/name" = "cloudnative-pg";
            };
          };
        };
      };

      resources.database = {
        ExternalSecret.pg0-lillecarl = hlib.eso.mkBasic "name:lillecarl-db";
        # Configure podmonitoring from CNPG docs
        Cluster.pg0.spec = {
          # Required to manage roles properly
          enableSuperuserAccess = true;
          instances = 2;
          storage.size = "10Gi";
          storage.storageClass = "hcloud-volumes";
          enablePDB = true;
          nodeMaintenanceWindow = lib.mkIf false {
            # Use this config if using local volumes
            inProgress = true;
            reusePVC = false;
          };
          managed.roles = lib.mkNamedList {
            lillecarl = {
              login = true;
              superuser = true;
              passwordSecret.name = "pg0-lillecarl";
            };
          };
        };
        VMPodScrape = lib.mkIf (config.kubernetes.apiMappings.VMPodScrape or false != false) {
          pg0 = {
            spec = {
              podMetricsEndpoints = [
                {
                  path = "/metrics";
                  port = "metrics";
                  scheme = "http";
                }
              ];
              selector.matchLabels = {
                "cnpg.io/cluster" = "pg0";
              };
              namespaceSelector = { };
            };
          };
        };
        Database.lillecarl.spec = {
          name = "lillecarl";
          owner = "lillecarl";
          cluster.name = "pg0";
          databaseReclaimPolicy = "delete";
        };
      };
      apiMappings = {
        "Backup" = "postgresql.cnpg.io/v1";
        "ClusterImageCatalog" = "postgresql.cnpg.io/v1";
        "Cluster" = "postgresql.cnpg.io/v1";
        "Database" = "postgresql.cnpg.io/v1";
        "FailoverQuorum" = "postgresql.cnpg.io/v1";
        "ImageCatalog" = "postgresql.cnpg.io/v1";
        "Pooler" = "postgresql.cnpg.io/v1";
        "Publication" = "postgresql.cnpg.io/v1";
        "ScheduledBackup" = "postgresql.cnpg.io/v1";
        "Subscription" = "postgresql.cnpg.io/v1";
      };
    };
  };
}
