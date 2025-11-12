{ config, lib, ... }:
{
  config = lib.mkIf (config.stage == "capi") {
    capi.enable = true;
  };
}
