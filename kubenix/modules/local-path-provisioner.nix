{
  config,
  pkgs,
  lib,
  ...
}:
let
  moduleName = "local-path-provisioner";
  cfg = config.${moduleName};
in
{
  options.${moduleName} = {
    enable = lib.mkEnableOption moduleName;
    version = lib.mkOption {
      type = lib.types.nonEmptyStr;
      default = "0.0.33";
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
        owner = "rancher";
        repo = "local-path-provisioner";
        ref = "v${cfg.version}";
      };
    in
    lib.mkIf cfg.enable {
      helm.releases.${moduleName} = {
        namespace = "kube-system";
        chart = "${src}/deploy/chart/local-path-provisioner";

        values = lib.recursiveUpdate {
          nodePathMap = [
            {
              node = "DEFAULT_PATH_FOR_NON_LISTED_NODES";
              paths = [ "/var/lib/local-path-provisioner" ];
            }
          ];
        } cfg.helmValues;
      };
    };
}
