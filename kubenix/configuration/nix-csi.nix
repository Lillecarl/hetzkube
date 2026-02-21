{ ... }:
{
  config = {
    nix-csi = {
      namespace = "nix-csi";
      node.compat = false; # only needed to transition from old nixkube to new hetzkube csi driver name
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
