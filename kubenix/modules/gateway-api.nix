{
  config,
  lib,
  ...
}:
let
  moduleName = "gateway-api";
  cfg = config.${moduleName};
in
{
  options.${moduleName} = {
    enable = (lib.mkEnableOption moduleName) // {
      default = true;
    };
    version = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = "1.2.0"; # https://docs.cilium.io/en/stable/network/servicemesh/gateway-api/gateway-api/#cilium-gateway-api-support
    };
  };
  config = lib.mkIf cfg.enable {
    importyaml.${moduleName} = {
      src = "https://github.com/kubernetes-sigs/gateway-api/releases/download/v${cfg.version}/standard-install.yaml";
    };
  };
}
