{
  pkgs,
  pkgsArm,
  easykubenix,
  nix-csi,
  args,
}:
let
  inherit (pkgs) lib;
  stage =
    if lib.hasAttr "stage" args then
      args.stage
    else
      builtins.trace ''
        Please specify a stage using the following arguments:
        --argstr stage $stage
      '' "full";
in
import easykubenix {
  inherit pkgs;
  specialArgs = {
    inherit pkgsArm;
  };
  modules = [
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
