{ config, lib, ... }:
{
  config = lib.mkIf (config.stage == "full") {
    flux = {
      enable = true;
      version = "2.7.5";
    };
  };
}
