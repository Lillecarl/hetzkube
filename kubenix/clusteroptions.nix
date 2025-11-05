{ lib, ... }:
{
  options = {
    clusterName = lib.mkOption {
      type = lib.types.nonEmptyStr;
    };
    clusterHost = lib.mkOption {
      type = lib.types.nonEmptyStr;
    };
  };
}
