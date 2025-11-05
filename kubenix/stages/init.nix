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
      hccm = {
        enable = true;
        apiToken = "{{ hctoken }}";
        helmValues = {
          # Disable HCCM LB
          env.HCLOUD_LOAD_BALANCERS_ENABLED.value = "false";
          env.HCLOUD_NETWORK_ROUTES_ENABLED.value = "false";
          env.HCLOUD_NETWORK_DISABLE_ATTACHED_CHECK.value = "true";
          # We must IPv6!!
          env.HCLOUD_INSTANCES_ADDRESS_FAMILY.value = "dualstack";
          additionalTolerations = [
            {
              key = "node.cilium.io/agent-not-ready";
              operator = "Exists";
            }
          ];
        };
      };
      cilium = {
        enable = true;
        k8sServiceHost = "kubernetes.lillecarl.com";
      };
    }
    ../.
  ];
}
