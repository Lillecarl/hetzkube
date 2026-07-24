{
  config,
  lib,
  hlib,
  ...
}:
{
  config =
    let
      cfTokenName = "cloudflare-token";
      scKeyName = "scaleway-dns-key";
    in
    lib.mkIf (config.stage == "full") {
      external-dns = {
        enable = true;
        instances.cloudflare = {
          enable = true;
          namespace = "kube-system";
          args = [
            "--source=crd"
            "--source=gateway-httproute"
            "--source=ingress"
            "--source=service"
            "--provider=cloudflare"
            "--txt-owner-id=${config.clusterName}"
          ];
          env = [
            {
              name = "CF_API_TOKEN";
              valueFrom = {
                secretKeyRef = {
                  name = cfTokenName;
                  key = "token";
                };
              };
            }
          ];
        };
        instances.scaleway = {
          enable = true;
          namespace = "kube-system";
          args = [
            "--source=crd"
            "--source=gateway-httproute"
            "--source=ingress"
            "--source=service"
            "--provider=scaleway"
            "--txt-owner-id=${config.clusterName}"
          ];
          env = [
            {
              name = "SCW_ACCESS_KEY";
              valueFrom = {
                secretKeyRef = {
                  name = scKeyName;
                  key = "username";
                };
              };
            }
            {
              name = "SCW_SECRET_KEY";
              valueFrom = {
                secretKeyRef = {
                  name = scKeyName;
                  key = "password";
                };
              };
            }
          ];
        };
      };
      kubernetes.objects = {
        kube-system.ExternalSecret.${cfTokenName} = hlib.eso.mkToken "name:${cfTokenName}";
        kube-system.ExternalSecret.${scKeyName} = hlib.eso.mkBasic "name:${scKeyName}";
      };
    };
}
