{
  config,
  pkgs,
  lib,
  ...
}:
let
  moduleName = "flux";
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
    importyaml.flux.src = "https://github.com/fluxcd/flux2/releases/download/v${cfg.version}/install.yaml";
  };
}
