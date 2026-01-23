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
    sha256 = lib.mkOption {
      type = lib.types.nonEmptyStr;
      default = lib.fakeHash;
    };
    helmValues = lib.mkOption {
      type = lib.types.anything;
      default = { };
    };
  };
  config = lib.mkIf cfg.enable {
    helm.releases.${moduleName} = {
      inherit (cfg) namespace;
      chart = pkgs.fetchHelm {
        chart = "kyverno";
        repo = "https://kyverno.github.io/kyverno/";
        inherit (cfg) version sha256;
      };

      values = lib.recursiveUpdate { } cfg.helmValues;
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
