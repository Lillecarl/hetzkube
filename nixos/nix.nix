{
  config,
  pkgs,
  lib,
  ...
}:
{
  config = {
    nix = {
      package = pkgs.lix;
    };
  };
}
