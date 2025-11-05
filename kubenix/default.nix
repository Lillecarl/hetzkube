{
  config,
  pkgs,
  lib,
  ...
}:
{
  imports = [
    ./capi.nix
    ./cilium.nix
    ./hccm.nix
  ];
  options = {
    clusterName = lib.mkOption {
      type = lib.types.nonEmptyStr;
    };
  };
  config = {
    kubernetes.resources.kube-public.ConfigMap.initialized = { };
  };
}
