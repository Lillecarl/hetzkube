{
  config,
  lib,
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
      default = "https://raw.githubusercontent.com/cloudnative-pg/cloudnative-pg/release-1.27/releases/cnpg-1.27.0.yaml";
    };
  };
  config = lib.mkIf cfg.enable {
    importyaml.${moduleName} = {
      src = cfg.url;
    };
    kubernetes = {
      resources.none.Namespace.cnpg-user = { };
      resources.cnpg-user = {
        Secret.pg0-lillecarl.stringData = {
          username = "lillecarl";
          password = "{{ lillepass }}";
        };
        Cluster.pg0 = {
          spec = {
            instances = 2;
            storage.size = "1Gi";
            monitoring.enablePodMonitor = true;
            managed.roles = {
              _namedlist = true;
              lillecarl = {
                comment = "Carl Andersson";
                login = true;
                superuser = true;
                passwordSecret.name = "pg0-lillecarl";
              };
            };
          };
        };
        Pooler.pb0 = {
          spec = {
            cluster.name = "pg0";
            instances = 1;
            type = "rw";
            serviceTemplate = {
              metadata.labels.app = "pooler";
              metadata.annotations."metallb.io/allow-shared-ip" = "true";
              spec.type = "LoadBalancer";
            };
            pgbouncer = {
              poolMode = "session";
              parameters = { };
            };
          };
        };
        Database.keycloak = {
          spec = {
            name = "keycloak";
            owner = "lillecarl";
            cluster.name = "pg0";
            databaseReclaimPolicy = "delete";
          };
        };
        Database.grafana = {
          spec = {
            name = "grafana";
            owner = "lillecarl";
            cluster.name = "pg0";
            databaseReclaimPolicy = "delete";
          };
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
