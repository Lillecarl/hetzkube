{ config, lib, ... }:
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
    clusterPodCIDR4 = lib.mkOption {
      type = lib.types.nonEmptyStr;
    };
    clusterServiceCIDR4 = lib.mkOption {
      type = lib.types.nonEmptyStr;
    };
    clusterPodCIDR6 = lib.mkOption {
      type = lib.types.nonEmptyStr;
    };
    clusterServiceCIDR6 = lib.mkOption {
      type = lib.types.nonEmptyStr;
    };
    clusterPodCIDR = lib.mkOption {
      internal = true;
      type = lib.types.listOf lib.types.nonEmptyStr;
    };
    clusterServiceCIDR = lib.mkOption {
      internal = true;
      type = lib.types.listOf lib.types.nonEmptyStr;
    };
  };
  config = {
    clusterPodCIDR = [
      config.clusterPodCIDR4
      config.clusterPodCIDR6
    ];
    clusterServiceCIDR = [
      config.clusterServiceCIDR4
      config.clusterServiceCIDR6
    ];
  };
}
