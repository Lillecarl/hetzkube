{ config, ... }:
{
  config = {
    nixkube = {
      # enable = config.stage == "full";
      enable = false;
      node.compat = false;
      push = true;
      pynixd = {
        enable = true;
        storageClassName = "hcloud-volumes";
        authorizedKeys = [
          (builtins.readFile ../../pubkeys/carl.pub)
          (builtins.readFile ../../pubkeys/lillecarlworld.pub)
        ];
      };
      metadata.labels = {
        "cilium.io/ingress" = "true";
      };
      loggingConfig = {
        renderer = "console";
        loggers = {
          nixkube.level = "DEBUG";
        };
      };
    };
  };
}
