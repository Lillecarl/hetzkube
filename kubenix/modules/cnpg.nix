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
      default = "https://raw.githubusercontent.com/cloudnative-pg/cloudnative-pg/release-1.27/releases/cnpg-1.27.1.yaml";
    };
  };
  config = lib.mkIf cfg.enable {
    importyaml.${moduleName} = {
      src = cfg.url;
    };
    kubernetes = {
      resources.none.Namespace.cnpg-user = { };
      resources.cnpg-user = {
        Secret.pg0-lillecarl = {
          type = "kubernetes.io/basic-auth";
          metadata.labels."cnpg.io/reload" = "true";
          stringData = {
            username = "lillecarl";
            password = "{{ lillepass }}";
          };
        };
        # Configure podmonitoring from CNPG docs
        Cluster.pg0.spec = {
          # Required to manage roles properly
          enableSuperuserAccess = true;
          instances = 2;
          storage.size = "1Gi";
          storage.storageClass = "local-path";
          enablePDB = true;
          # Create new pods and stream database to replicas
          nodeMaintenanceWindow = {
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
        Pooler.pb0-lb = {
          spec = {
            cluster.name = "pg0";
            instances = 1;
            type = "rw";
            serviceTemplate = {
              metadata.labels.app = "pooler";
              metadata.labels."cilium.io/ingress" = "true";
              metadata.annotations."metallb.io/allow-shared-ip" = "true";
              metadata.annotations."lbipam.cilium.io/sharing-key" = "*";
              metadata.annotations."lbipam.cilium.io/sharing-cross-namespace" = "*";
              spec.type = "LoadBalancer";
            };
            pgbouncer = {
              poolMode = "session";
              parameters = { };
            };
          };
        };
        Pooler.pb0-cluster = {
          spec = {
            cluster.name = "pg0";
            instances = 1;
            type = "rw";
            pgbouncer.poolMode = "session";
          };
        };
        Database.lillecarl.spec = {
          name = "lillecarl";
          owner = "lillecarl";
          cluster.name = "pg0";
          databaseReclaimPolicy = "delete";
        };
        Database.grafana.spec = {
          name = "grafana";
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
