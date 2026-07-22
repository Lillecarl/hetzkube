{
  pkgs,
  pkgsOff,
  easykubenix,
  nix-csi,
  args,
}:
let
  inherit (pkgs) lib;
  # "full" is the day-to-day default -- "capi" only matters when
  # bootstrapping a brand new cluster from scratch (see README.md), a
  # one-time concern, not something worth nagging about on every eval.
  stage = args.stage or "full";
in
import easykubenix {
  inherit pkgs;
  modules = [
    {
      _module.args = {
        inherit pkgsOff;
      };
    }
    ./modules
    ./capi
    ./full
    ./configuration
    "${nix-csi}/kubenix"
    {
      config = {
        kluctl.discriminator = stage;
        inherit stage;
      };
    }
  ];
}
