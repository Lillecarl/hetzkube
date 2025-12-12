{
  config,
  lib,
  ...
}:
let
  moduleName = "hcsi";
  cfg = config.${moduleName};
in
{
  options.${moduleName} = {
    enable = lib.mkEnableOption moduleName;
    apiToken = lib.mkOption {
      type = lib.types.str;
    };
    version = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = "2.18.2";
    };
  };
  config = lib.mkIf cfg.enable {
    importyaml.${moduleName} = {
      src = "https://raw.githubusercontent.com/hetznercloud/csi-driver/v${cfg.version}/deploy/kubernetes/hcloud-csi.yml";
    };
  };
}
