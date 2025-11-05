{
  pkgs ? import <nixpkgs> { },
}:
let
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
      clusterName = "hetzkube";
      cilium = {
        enable = true;
        k8sServiceHost = "kubernetes.lillecarl.com";
      };
      hccm = {
        enable = true;
        apiToken = "{{ hctoken }}";
      };
    }
    ./kubenix
  ];
}
