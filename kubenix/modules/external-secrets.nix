{
  config,
  pkgs,
  lib,
  ...
}:
let
  moduleName = "external-secrets";
  cfg = config.${moduleName};
in
{
  options.${moduleName} = {
    enable = lib.mkEnableOption moduleName;
    refreshInterval = lib.mkOption {
      description = "Interval between secrets refreshing";
      type = lib.types.str;
      default = "30m0s";
    };
    version = lib.mkOption {
      type = lib.types.nonEmptyStr;
      default = "2.8.0";
    };
    helmValues = lib.mkOption {
      type = lib.types.anything;
      default = { };
    };
  };
  config = lib.mkIf cfg.enable {
    kubernetes.resources.none.ClusterGenerator.crappy-pw = {
      spec = {
        kind = "Password";
        generator.passwordSpec = {
          length = 16;
          symbols = 0;
        };
      };
    };
    helm.releases.${moduleName} = {
      namespace = "kube-system";

      chart = builtins.fetchTree {
        type = "tarball";
        url = "https://github.com/external-secrets/external-secrets/releases/download/helm-chart-${cfg.version}/external-secrets-${cfg.version}.tgz";
      };

      values = lib.recursiveUpdate {
        image.tag = lib.mkDefault "v${cfg.version}";
        certManager.enabled = lib.mkDefault config.cert-manager.enable;
      } cfg.helmValues;
    };
    hlib.eso = let
      resolveKey = identifier: storeName:
        if storeName == "infisical" && lib.hasPrefix "name:" identifier
        then lib.removePrefix "name:" identifier
        else identifier;
    in rec {
      mkBasic = arg:
        let
          identifier = if lib.isString arg then arg else arg.identifier;
          storeName = if lib.isString arg then "scaleway" else arg.storeName or "scaleway";
          key = resolveKey identifier storeName;
        in {
          spec = {
            refreshInterval = cfg.refreshInterval;
            secretStoreRef = {
              kind = "ClusterSecretStore";
              name = storeName;
            };
            target.template.type = "kubernetes.io/basic-auth";
            data = [
              {
                secretKey = "username";
                remoteRef = {
                  key = key;
                  property = "username";
                };
              }
              {
                secretKey = "password";
                remoteRef = {
                  key = key;
                  property = "password";
                };
              }
            ];
          };
        };
      mkToken = arg:
        let
          identifier = if lib.isString arg then arg else arg.identifier;
          storeName = if lib.isString arg then "scaleway" else arg.storeName or "scaleway";
        in mkOpaque { identifier = identifier; secretKey = "token"; inherit storeName; };
      mkOpaque = arg:
        if lib.isString arg then
          secretKey: mkOpaque { identifier = arg; inherit secretKey; }
        else let
          secretKey = arg.secretKey;
          identifier = arg.identifier;
          storeName = arg.storeName or "scaleway";
          key = resolveKey identifier storeName;
        in {
          spec = {
            refreshInterval = cfg.refreshInterval;
            secretStoreRef = {
              kind = "ClusterSecretStore";
              name = storeName;
            };
            target.template.type = "Opaque";
            data = [
              {
                inherit secretKey;
                remoteRef.key = key;
              }
            ];
          };
        };
    };
    kubernetes.apiMappings = {
      ACRAccessToken = "generators.external-secrets.io/v1alpha1";
      CloudsmithAccessToken = "generators.external-secrets.io/v1alpha1";
      ClusterExternalSecret = "external-secrets.io/v1";
      ClusterGenerator = "generators.external-secrets.io/v1alpha1";
      ClusterPushSecret = "external-secrets.io/v1alpha1";
      ClusterSecretStore = "external-secrets.io/v1";
      ECRAuthorizationToken = "generators.external-secrets.io/v1alpha1";
      ExternalSecret = "external-secrets.io/v1";
      Fake = "generators.external-secrets.io/v1alpha1";
      GCRAccessToken = "generators.external-secrets.io/v1alpha1";
      GeneratorState = "generators.external-secrets.io/v1alpha1";
      GithubAccessToken = "generators.external-secrets.io/v1alpha1";
      # Grafana = "generators.external-secrets.io/v1alpha1";
      MFA = "generators.external-secrets.io/v1alpha1";
      Password = "generators.external-secrets.io/v1alpha1";
      PushSecret = "external-secrets.io/v1alpha1";
      QuayAccessToken = "generators.external-secrets.io/v1alpha1";
      SSHKey = "generators.external-secrets.io/v1alpha1";
      STSSessionToken = "generators.external-secrets.io/v1alpha1";
      SecretStore = "external-secrets.io/v1";
      UUID = "generators.external-secrets.io/v1alpha1";
      VaultDynamicSecret = "generators.external-secrets.io/v1alpha1";
      Webhook = "generators.external-secrets.io/v1alpha1";
    };
    kubernetes.namespacedMappings = {
      ACRAccessToken = true;
      CloudsmithAccessToken = true;
      ClusterExternalSecret = false;
      ClusterGenerator = false;
      ClusterPushSecret = false;
      ClusterSecretStore = false;
      ECRAuthorizationToken = true;
      ExternalSecret = true;
      Fake = true;
      GCRAccessToken = true;
      GeneratorState = true;
      GithubAccessToken = true;
      Grafana = true;
      MFA = true;
      Password = true;
      PushSecret = true;
      QuayAccessToken = true;
      SSHKey = true;
      STSSessionToken = true;
      SecretStore = true;
      UUID = true;
      VaultDynamicSecret = true;
      Webhook = true;
    };
  };
}
