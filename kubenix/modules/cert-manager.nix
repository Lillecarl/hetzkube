{
  config,
  lib,
  ...
}:
let
  moduleName = "cert-manager";
  cfg = config.${moduleName};
in
{
  options.${moduleName} = {
    enable = lib.mkEnableOption moduleName;
    version = lib.mkOption {
      type = lib.types.nonEmptyStr;
    };
  };
  config = lib.mkIf cfg.enable {
    importyaml.${moduleName} = {
      src = "https://github.com/cert-manager/cert-manager/releases/download/v${cfg.version}/cert-manager.yaml";
    };
    kubernetes.objects.cert-manager.VMServiceScrape = {
      cert-manager = {
        spec = {
          selector.matchLabels = {
            "app.kubernetes.io/instance" = "cert-manager";
            "app.kubernetes.io/name" = "cert-manager";
          };
          endpoints = [
            {
              port = "tcp-prometheus-serv";
              path = "/metrics";
              interval = "30s";
            }
          ];
        };
      };

      cert-manager-cainjector = {
        spec = {
          selector.matchLabels = {
            "app.kubernetes.io/instance" = "cert-manager";
            "app.kubernetes.io/name" = "cainjector";
          };
          endpoints = [
            {
              port = "tcp-prometheus-serv";
              path = "/metrics";
              interval = "30s";
            }
          ];
        };
      };

      cert-manager-webhook = {
        spec = {
          selector.matchLabels = {
            "app.kubernetes.io/instance" = "cert-manager";
            "app.kubernetes.io/name" = "webhook";
          };
          endpoints = [
            {
              port = "https"; # Port 9402 on the webhook service
              path = "/metrics";
              interval = "30s";
            }
          ];
        };
      };
    };
    kubernetes.apiMappings = {
      Certificate = "cert-manager.io/v1";
      CertificateRequest = "cert-manager.io/v1";
      Challenge = "acme.cert-manager.io/v1";
      ClusterIssuer = "cert-manager.io/v1";
      Issuer = "cert-manager.io/v1";
      Order = "acme.cert-manager.io/v1";
    };
    kubernetes.namespacedMappings = {
      Certificate = true;
      CertificateRequest = true;
      Challenge = true;
      ClusterIssuer = true;
      Issuer = true;
      Order = true;
    };
  };
}
