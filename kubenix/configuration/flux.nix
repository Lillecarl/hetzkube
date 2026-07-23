{ config, lib, ... }:
{
  config = lib.mkIf (config.stage == "full") {
    flux = {
      # Disabled: Kyverno/VPA/grafana-operator (Flux's only HelmReleases)
      # moved to kubenix's own local Helm rendering (helm.releases), so
      # nothing left needs Flux's controllers. Left declared rather than
      # removed in case it's needed again.
      enable = false;
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
