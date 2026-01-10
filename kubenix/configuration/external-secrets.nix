{
  config,
  pkgs,
  lib,
  eso,
  ...
}:
{
  config = lib.mkIf (config.stage == "full") {
    external-secrets = {
      enable = true;
    };
    kubernetes.resources.kube-system.Secret.scaleway.stringData = {
      SCW_ACCESS_KEY = "{{ SCW_ACCESS_KEY }}";
      SCW_SECRET_KEY = "{{ SCW_SECRET_KEY }}";
    };
    kubernetes.resources.none.ClusterSecretStore.scaleway = {
      spec = {
        provider.scaleway = {
          region = "nl-ams";
          projectId = "cbc08bd9-d5af-4258-b8b7-21f5d5ae481a";
          accessKey.secretRef = {
            namespace = "kube-system";
            name = "scaleway";
            key = "SCW_ACCESS_KEY";
          };
          secretKey.secretRef = {
            namespace = "kube-system";
            name = "scaleway";
            key = "SCW_SECRET_KEY";
          };
        };
      };
    };
  };
}
