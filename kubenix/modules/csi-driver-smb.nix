{
  config,
  pkgs,
  lib,
  ...
}:
let
  moduleName = "csi-driver-smb";
  cfg = config.${moduleName};
in
{
  options.${moduleName} = {
    enable = lib.mkEnableOption moduleName;
    version = lib.mkOption {
      type = lib.types.nonEmptyStr;
      default = "1.19.1";
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
        owner = "kubernetes-csi";
        repo = "csi-driver-smb";
        ref = "v${cfg.version}";
      };
    in
    lib.mkIf cfg.enable {
      helm.releases.${moduleName} = {
        namespace = "kube-system";
        chart = "${src}/charts/v${cfg.version}/csi-driver-smb";

        values = lib.recursiveUpdate {
          windows.enable = lib.mkDefault false;
        } cfg.helmValues;
      };
    };
}
