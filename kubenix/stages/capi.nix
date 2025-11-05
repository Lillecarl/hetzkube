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
      clusterName = "hetzkube";
      capi = {
        enable = true;
        controlPlaneHost = "kubernetes.lillecarl.com";
      };
    }
    ./kubenix
  ];
}
