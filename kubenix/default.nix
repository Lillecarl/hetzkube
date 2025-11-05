{
  pkgs,
  easykubenix,
  args,
}:
let
  inherit (pkgs) lib;
  stage =
    if lib.hasAttr "stage" args then
      args.stage
    else
      throw ''
        You must specify a stage using the following arguments:
        --argstr stage $stage
      '';

  stages = rec {
    # Only on some ephemeral init cluster
    capi = {
      capi.enable = true;
    };
    # This is run by CAPI as a postKubeadmCommand on the first node.
    # Don't run this unless you know what you're doing++
    init = {
      cilium.enable = true;
      hccm.enable = true;
      cert-manager = {
        enable = true;
        bare = true;
      };
    };
    # Don't run full stage until you've migrated CAPI into the cluster
    full = lib.recursiveUpdate init {
      capi.enable = true;
    };
  };
  stageMod = stages.${stage};
in
easykubenix {
  inherit pkgs;
  modules = [
    ./capi.nix
    ./cert-manager.nix
    ./cilium.nix
    ./clusteroptions.nix
    ./hccm.nix
    stageMod
    {
      config = {
        kluctl = {
          discriminator = stage;
          deployment.vars = [ { file = "secrets/all.yaml"; } ];
          files."secrets/all.yaml" = builtins.readFile ../secrets/all.yaml;
        };
        clusterName = "hetzkube";
        clusterHost = "kubernetes.lillecarl.com";

        cert-manager.email = "le@lillecarl.com";
        hccm = {
          apiToken = "{{ hctoken }}";
          helmValues = {
            # Only use HCCM to assign providerID
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
        kubernetes.resources.kube-public.ConfigMap.initialized = { };
      };
    }
  ];
}
