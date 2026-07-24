{
  config,
  pkgs,
  lib,
  ...
}:
{
  # Shell prompt
  programs.starship = {
    enable = true;
    enableFishIntegration = true;
  };
  # Actually good shell
  programs.fish = {
    enable = true;
    shellAbbrs = {
      kc = "kubectl";
      sc = "sudo systemctl";
    };
  };
}
