{ ... }:
{
  config = {
    nix-csi = {
      namespace = "nix-csi";
      internalServiceName = "hetzkube";
      cache.enable = true;
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
        version = 1;
        formatters = {
          standard = {
            format = "%(levelname)s [%(name)s] %(message)s";
          };
        };
        handlers = {
          console = {
            class = "logging.StreamHandler";
            formatter = "standard";
            stream = "ext://sys.stdout";
          };
        };
        loggers = {
          nix-csi = {
            level = "DEBUG";
            handlers = [ "console" ];
            propagate = false;
          };
          httpx = {
            level = "WARNING";
            handlers = [ "console" ];
            propagate = false;
          };
        };
        root = {
          level = "INFO";
          handlers = [ "console" ];
        };
      };
    };
  };
}
