{ pkgs ? import <nixpkgs> {} }:
let
  steampipe-fhs = pkgs.buildFHSEnvBubblewrap {
    name = "steampipe";
    targetPkgs = p: [ p.steampipe ];
    runScript = "steampipe";
  };
in
{
  inherit steampipe-fhs;
}
