{
  config,
  pkgs,
  lib,
  ...
}:
let
  mkKC =
    attrs:
    attrs
    // {
      realm_id = lib.tfRef "local.realm_id";
    };
in
{
  config = {
    terraform = {
      required_providers = {
        keycloak = {
          source = "keycloak/keycloak";
          version = "5.5.0";
        };
      };
    };
    provider.keycloak = {
      client_id = "admin-cli";
      url = "https://keycloak.lillecarl.com";
    };
    data.keycloak_realm.this.realm = "master";
    locals.realm_id = config.data.keycloak_realm.this "id";

    resource.keycloak_openid_client.kubernetes = mkKC {
      client_id = "kubernetes";
      name = "Kubernetes";

      valid_redirect_uris = [
        # Kubelogin runs some local webserver here when setting up OIDC tokens
        "http://localhost:8000"
      ];

      standard_flow_enabled = true;
      direct_access_grants_enabled = false;
      service_accounts_enabled = false;
      access_type = "PUBLIC";
    };

    resource.keycloak_openid_group_membership_protocol_mapper.kubernetes = mkKC {
      client_id = config.resource.keycloak_openid_client.kubernetes "id";
      name = "Group Membership";

      claim_name = "groups";
      full_path = false;
    };

    resource.keycloak_openid_client.headlamp = mkKC {
      client_id = "headlamp";
      name = "Headlamp";

      valid_redirect_uris = [
        "https://headlamp.e.lillecarl.com/oidc-callback"
      ];

      standard_flow_enabled = true;
      direct_access_grants_enabled = false;
      service_accounts_enabled = false;
      access_type = "CONFIDENTIAL";
      access_token_lifespan = "28800"; # 8 hour tokens
    };

    resource.keycloak_openid_group_membership_protocol_mapper.headlamp = mkKC {
      client_id = config.resource.keycloak_openid_client.headlamp "id";
      name = "Group Membership";

      claim_name = "groups";
      full_path = false;
    };

    # Add kubernetes audience for headlamp since it passes it's oidc token onto Kubernetes
    resource.keycloak_openid_audience_protocol_mapper.headlamp_kubernetes_audience = mkKC {
      client_id = config.resource.keycloak_openid_client.headlamp "id";
      name = "Kubernetes Audience";
      included_client_audience = config.resource.keycloak_openid_client.kubernetes.client_id;
      add_to_id_token = true;
    };

    resource.keycloak_openid_client.grafana = mkKC {
      client_id = "grafana";
      name = "Grafana";

      valid_redirect_uris = [
        "https://grafana.e.lillecarl.com/login/generic_oauth"
      ];

      standard_flow_enabled = true;
      direct_access_grants_enabled = true;
      service_accounts_enabled = false;
      access_type = "CONFIDENTIAL";
      access_token_lifespan = "28800"; # 8 hour tokens
    };

    resource.keycloak_openid_group_membership_protocol_mapper.grafana = mkKC {
      client_id = config.resource.keycloak_openid_client.grafana "id";
      name = "Group Membership";

      claim_name = "groups";
      full_path = false;
    };

    resource.keycloak_group.kubernetes-admin = mkKC {
      name = "kubernetes-admin";
    };

    resource.keycloak_group.grafana-admin = mkKC {
      name = "grafana-admin";
    };
  };
}
