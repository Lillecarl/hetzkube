{
  config,
  pkgs,
  lib,
  ...
}:
let
  moduleName = "kro";
  cfg = config.${moduleName};
in
{
  options.${moduleName} = {
    enable = lib.mkEnableOption moduleName;
    version = lib.mkOption {
      type = lib.types.nonEmptyStr;
      default = "0.7.0";
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
        owner = "kubernetes-sigs";
        repo = "kro";
        ref = "v${cfg.version}";
      };
    in
    lib.mkIf cfg.enable {
      helm.releases.${moduleName} = {
        namespace = "kube-system";
        chart = "${src}/helm";

        values = lib.recursiveUpdate {
          image.tag = "v${cfg.version}";
        } cfg.helmValues;
      };
    };
}
