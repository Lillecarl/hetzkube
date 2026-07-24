{ config, lib, ... }:
let
  # Same Scaleway project/region ESO's ClusterSecretStore already reads from
  # (kubenix/configuration/external-secrets.nix) -- kubenix's ESO wiring
  # looks these up by name ("name:<secret-name>"), so the `name` here must
  # match exactly.
  region = "nl-ams";
  projectId = "cbc08bd9-d5af-4258-b8b7-21f5d5ae481a";

  mkSecret = key: dataRef: {
    resource.scaleway_secret."vmalert-oauth2-proxy-${key}" = {
      name = "vmalert-oauth2-proxy-${key}";
      inherit region;
      project_id = projectId;
    };
    resource.scaleway_secret_version."vmalert-oauth2-proxy-${key}" = {
      inherit region;
      secret_id = config.resource.scaleway_secret."vmalert-oauth2-proxy-${key}" "id";
      data = dataRef;
    };
  };
in
{
  config = lib.mkMerge [
    {
      resource.random_password.vmalert-oauth2-proxy-cookie = {
        length = 32;
        special = false;
      };
    }
    (mkSecret "client-secret" (config.resource.keycloak_openid_client.vmalert "client_secret"))
    (mkSecret "cookie-secret" (config.resource.random_password.vmalert-oauth2-proxy-cookie "result"))
  ];
}
