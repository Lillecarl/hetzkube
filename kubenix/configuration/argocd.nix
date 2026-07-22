{ config, lib, ... }:
{
  config = lib.mkIf (config.stage == "full") {
    argocd = {
      enable = true;
      version = "3.4.5";
      ksops.enable = true;
    };
  };
}
