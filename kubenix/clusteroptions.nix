{ lib, ... }:
{
  options = {
    clusterName = lib.mkOption {
      type = lib.types.nonEmptyStr;
    };
    clusterHost = lib.mkOption {
      type = lib.types.nonEmptyStr;
    };
    clusterDomain = lib.mkOption {
      type = lib.types.nonEmptyStr;
      default = "cluster.local";
    };
    clusterDNS = lib.mkOption {
      type = lib.types.listOf lib.types.nonEmptyStr;
    };
    clusterPodCIDR = lib.mkOption {
      type = lib.types.listOf lib.types.nonEmptyStr;
    };
    clusterServiceCIDR = lib.mkOption {
      type = lib.types.listOf lib.types.nonEmptyStr;
    };
  };
}
