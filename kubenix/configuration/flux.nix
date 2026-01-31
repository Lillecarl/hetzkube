{ config, lib, ... }:
{
  config = lib.mkIf (config.stage == "full") {
    flux = {
      enable = true;
      version = "2.7.5";
    };

    kubernetes.transformers = [
      (
        resource:
        if resource.kind == "HelmRelease" then
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
