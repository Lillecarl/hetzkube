{
  config,
  lib,
  ...
}:
let
  moduleName = "sealed-secrets";
  cfg = config.${moduleName};
in
{
  options.${moduleName} = {
    enable = lib.mkEnableOption moduleName;
    version = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = "0.37.0";
    };
  };
  config = lib.mkIf cfg.enable {
    importyaml.${moduleName} = {
      src = "https://github.com/bitnami-labs/sealed-secrets/releases/download/v${cfg.version}/controller.yaml";
    };
  };
}
