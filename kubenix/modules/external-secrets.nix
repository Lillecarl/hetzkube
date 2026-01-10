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
      default = "1.1.1";
    };
    sha256 = lib.mkOption {
      type = lib.types.str;
      default = "sha256-yZ/3KiplxxHVVnuX4+kFXZ+Nd4Jq2oe+HZgeMqVp43Q=";
    };
    helmValues = lib.mkOption {
      type = lib.types.anything;
      default = { };
    };
  };
  config =
    let
      src = builtins.fetchTree {
        type = "github";
        owner = "external-secrets";
        repo = "external-secrets";
        ref = "helm-chart-${cfg.version}";
      };
    in
    lib.mkIf cfg.enable {
      helm.releases.${moduleName} = {
        namespace = "kube-system";
        chart = pkgs.fetchHelm {
          chart = "external-secrets";
          repo = "https://charts.external-secrets.io";
          inherit (cfg) version sha256;
        };

        values = lib.recursiveUpdate {
          image.tag = lib.mkDefault "v${cfg.version}";
          certManager.enabled = lib.mkDefault config.cert-manager.enable;
        } cfg.helmValues;
      };
      importyaml.${moduleName} = {
        src = "${src}/deploy/crds/bundle.yaml";
      };
      _module.args = {
        eso = rec {
          mkBasic = swIdentifier: {
            spec = {
              refreshInterval = cfg.refreshInterval;
              secretStoreRef = {
                kind = "ClusterSecretStore";
                name = "scaleway";
              };
              target.template.type = "kubernetes.io/basic-auth";
              data = [
                {
                  secretKey = "username";
                  remoteRef = {
                    key = swIdentifier;
                    property = "username";
                  };
                }
                {
                  secretKey = "password";
                  remoteRef = {
                    key = swIdentifier;
                    property = "password";
                  };
                }
              ];
            };
          };
          mkToken = swIdentifier: mkOpaque swIdentifier "token";
          mkOpaque = swIdentifier: secretKey: {
            spec = {
              refreshInterval = cfg.refreshInterval;
              secretStoreRef = {
                kind = "ClusterSecretStore";
                name = "scaleway";
              };
              target.template.type = "Opaque";
              data = [
                {
                  inherit secretKey;
                  remoteRef.key = swIdentifier;
                }
              ];
            };
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
        Grafana = "generators.external-secrets.io/v1alpha1";
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
