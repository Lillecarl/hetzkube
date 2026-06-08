{ config, ... }:
{
  config = {
    nixkube = {
      # enable = config.stage == "full";
      enable = false;
      node.compat = false;
      internalServiceName = "hetzkube";
      cache.enable = true;
      push = true;
      builders = {
        enable = true;
        deployments.builder-amd64 = {
          enable = true;
        };
      };
      cache.storageClassName = "hcloud-volumes";
      metadata.labels = {
        "cilium.io/ingress" = "true";
      };
      authorizedKeys = [
        (builtins.readFile ../../pubkeys/carl.pub)
        (builtins.readFile ../../pubkeys/lillecarlworld.pub)
      ];
      loggingConfig = {
        renderer = "console";
        loggers = {
          nixkube.level = "DEBUG";
        };
      };
    };
  };
}
