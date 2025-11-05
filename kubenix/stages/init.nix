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
        files."secrets/all.yaml" = builtins.readFile ../../secrets/all.yaml;
      };
      clusterName = "hetzkube";
      cilium = {
        enable = true;
        k8sServiceHost = "kubernetes.lillecarl.com";
      };
    }
    ../.
  ];
}
