{
  config,
  pkgs,
  lib,
  ...
}:
let
  moduleName = "kyverno";
  cfg = config.${moduleName};
in
{
  options.${moduleName} = {
    enable = lib.mkEnableOption moduleName;
    namespace = lib.mkOption {
      type = lib.types.nonEmptyStr;
      default = "kyverno";
    };
    version = lib.mkOption {
      type = lib.types.nonEmptyStr;
    };
    helmValues = lib.mkOption {
      type = lib.types.anything;
      default = { };
    };
  };
  config = lib.mkIf cfg.enable {
    kubernetes.resources.none.Namespace.${cfg.namespace} = { };

    kubernetes.resources.${cfg.namespace} = {
      HelmRepository.kyverno = {
        spec = {
          interval = "1h";
          url = "https://kyverno.github.io/kyverno";
        };
      };
      HelmRelease.kyverno = {
        spec = {
          chart = {
            spec = {
              chart = "kyverno";
              version = cfg.version;
              sourceRef = {
                kind = "HelmRepository";
                name = "kyverno";
                namespace = cfg.namespace;
              };
            };
          };
          values = lib.recursiveUpdate { } cfg.helmValues;
          interval = "1h";
          driftDetection = {
            mode = "enabled";
            ignore = [
              {
                target = {
                  kind = "Deployment";
                };
                paths = [
                  "/spec/template/spec/resources/requests"
                  "/spec/template/spec/containers/*/resources/requests"
                ];
              }
            ];
          };
        };
      };
    };

    kubernetes = {
      apiMappings = {
        CleanupPolicy = "kyverno.io/v2";
        ClusterCleanupPolicy = "kyverno.io/v2";
        ClusterPolicy = "kyverno.io/v1";
        GlobalContextEntry = "kyverno.io/v2beta1";
        Policy = "kyverno.io/v1";
        PolicyException = "kyverno.io/v2";
        UpdateRequest = "kyverno.io/v2";
        DeletingPolicy = "policies.kyverno.io/v1beta1";
        GeneratingPolicy = "policies.kyverno.io/v1beta1";
        ImageValidatingPolicy = "policies.kyverno.io/v1beta1";
        MutatingPolicy = "policies.kyverno.io/v1beta1";
        NamespacedDeletingPolicy = "policies.kyverno.io/v1beta1";
        NamespacedImageValidatingPolicy = "policies.kyverno.io/v1beta1";
        NamespacedValidatingPolicy = "policies.kyverno.io/v1beta1";
        # PolicyException = "policies.kyverno.io/v1beta1"; # who the fuck makes name collisions in their own operator, dumb shits
        ValidatingPolicy = "policies.kyverno.io/v1beta1";
        ClusterEphemeralReport = "reports.kyverno.io/v1";
        EphemeralReport = "reports.kyverno.io/v1";
      };
      namespacedMappings = {
        CleanupPolicy = true;
        ClusterCleanupPolicy = false;
        ClusterPolicy = false;
        GlobalContextEntry = false;
        Policy = true;
        PolicyException = true;
        UpdateRequest = true;
        DeletingPolicy = false;
        GeneratingPolicy = false;
        ImageValidatingPolicy = false;
        MutatingPolicy = false;
        NamespacedDeletingPolicy = true;
        NamespacedImageValidatingPolicy = true;
        NamespacedValidatingPolicy = true;
        # PolicyException = true; # who the fuck makes name collisions in their own operator, dumb shits
        ValidatingPolicy = false;
        ClusterEphemeralReport = false;
        EphemeralReport = true;
      };
    };
  };
}
