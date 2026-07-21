{ config, lib, ... }:
{
  config = lib.mkIf (config.stage == "full") {
    flux = {
      enable = true;
      version = "2.8.8";
    };

    kubernetes.transformers = [
      (
        resource:
        if resource.kind or null == "HelmRelease" then
          lib.recursiveUpdate {
            spec = {
              install = {
                crds = "CreateReplace";
                remediation.retries = 3;
              };
              upgrade = {
                crds = "CreateReplace";
                remediation.retries = 3;
              };
            };
          } resource
        else
          resource
      )
    ];
  };
}
