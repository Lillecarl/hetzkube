{
  pkgs,
  easykubenix,
}:
easykubenix {
  inherit pkgs;
  modules = [
    {
      kluctl = {
        discriminator = "capi";
        deployment.vars = [ { file = "secrets/all.yaml"; } ];
        files."secrets/all.yaml" = builtins.readFile ./secrets/all.yaml;
      };
      capi = {
        enable = true;
        clusterName = "hetzkube";
        controlPlaneHost = "kubernetes.lillecarl.com";
      };
    }
    ./kubenix
  ];
}
