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
      default = "1.19.1";
    };
  };
  config = lib.mkIf cfg.enable {
    importyaml.${moduleName} = {
      src = "https://github.com/cert-manager/cert-manager/releases/download/v${cfg.version}/cert-manager.yaml";
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
