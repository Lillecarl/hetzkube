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
    enable = lib.mkEnableOption moduleName;
    version = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
    };
  };
  config = lib.mkIf cfg.enable {
    importyaml.${moduleName} = {
      src = "https://github.com/kubernetes-sigs/gateway-api/releases/download/v${cfg.version}/standard-install.yaml";
    };
  };
}
