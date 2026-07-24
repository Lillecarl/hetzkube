{
  config,
  pkgs,
  lib,
  ...
}:
{
  config = lib.mkIf (config.stage == "full") {
    chaoskube.chaoskube = {
      enable = true;
      labels = {
        "chaos.alpha.kubernetes.io/disabled" = "";
      };
      args = {
        no-dry-run = "";
        interval = "15m";
        minimum-age = "6h";
        timezone = "Europe/Stockholm";
        # Don't kill primary databases, CNPG takes awhile to recover
        # Don't kill k8s control-plane components
        labels = "cnpg.io/instanceRole!=primary,tier!=control-plane";
        # Allow annotation to disable chaoskube targeting
        annotations = "!chaos.alpha.kubernetes.io/disabled";
      };
    };
  };
}
