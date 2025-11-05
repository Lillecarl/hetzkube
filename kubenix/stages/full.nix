{
  pkgs,
  easykubenix,
}:
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
      # capi.nix
      # To reconfigure the cluster with the cluster :)
      capi = {
        enable = true;
        controlPlaneHost = "kubernetes.lillecarl.com";
      };
      # init.nix
      # We need CNI to run CAPI and CAPH
      cilium = {
        enable = true;
        k8sServiceHost = "kubernetes.lillecarl.com";
      };
    }
    ./kubenix
  ];
}
