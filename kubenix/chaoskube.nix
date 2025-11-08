{
  config,
  lib,
  ...
}:
let
  moduleName = "chaoskube";
  cfg = config.${moduleName};
in
{
  options.${moduleName} = {
    enable = lib.mkEnableOption moduleName;
    helmValues = lib.mkOption {
      type = lib.types.anything;
      default = { };
    };
  };
  config =
    let
      version = "0.37.0";
    in
    lib.mkIf cfg.enable {
      helm.releases.${moduleName} = {
        namespace = "kube-system";
        chart = "${
          builtins.fetchTree {
            type = "github";
            owner = "linki";
            repo = "chaoskube";
            ref = "v${version}";
          }
        }/chart/chaoskube";

        values = {
          image.tag = "v${version}";
          chaoskube = {
            args = {
              no-dry-run = ""; # This makes things go poof
              interval = "15m";
              minimum-age = "6h";
              timezone = "Europe/Stockholm";
              # labels = "k8s-app!=cilium"; # Don't kill networking
            };
          };
        }
        // cfg.helmValues;
      };
    };
}
