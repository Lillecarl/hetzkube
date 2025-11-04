{
  pkgs ? import <nixpkgs> { },
}:
let
  clusterName = "hetzkube";
  easykubenix =
    let
      path = /home/lillecarl/Code/easykubenix;
    in
    if builtins.pathExists path then
      import path
    else
      import (
        builtins.fetchTree {
          type = "github";
          owner = "lillecarl";
          repo = "easykubenix";
        }
      );
in
easykubenix {
  inherit pkgs;
  modules = [
    {
      kluctl = {
        discriminator = "init";
        deployment.vars = [ { file = "secrets/all.yaml"; } ];
        files."secrets/all.yaml" = builtins.readFile ./secrets/all.yaml;
      };
    }
    ./kubenix
  ];
}
