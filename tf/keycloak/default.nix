{ config, lib, ... }:
let
  mkKC =
    attrs:
    attrs
    // {
      realm_id = lib.tfRef "local.realm_id";
    };

  data = config.data;
  resource = config.resource;
in
{
  config = {
    # TODO fix: mailgun secret doesn't exist yet
    # data.kubernetes_secret_v1.mailgun = {
    #   metadata = {
    #     name = "mailgun";
    #     namespace = "observability";
    #   };
    # };

    locals.realm_id = config.resource.keycloak_realm.auth "id";
    resource.keycloak_realm.auth = {
      realm = "auth";
      enabled = true;
      display_name = "Auth";
      display_name_html = "<b>Auth</b>";

      registration_allowed = true;
      registration_email_as_username = true;
      edit_username_allowed = true;
      reset_password_allowed = true;
      remember_me = true;
      verify_email = true;
      login_with_email_allowed = true;

      attributes = { };

      # TODO fix: mailgun SMTP config depends on mailgun secret above
      # smtp_server = {
      #   host = "smtp.eu.mailgun.org";
      #   port = 587;
      #   starttls = true;

      #   from = "auth@mg.lillecarl.com";

      #   auth = {
      #     username = data.kubernetes_secret_v1.mailgun "data.username";
      #     password = data.kubernetes_secret_v1.mailgun "data.password";
      #   };
      # };
    };

    resource.keycloak_realm_user_profile.auth =
      let
        permissions = {
          view = [
            "admin"
            "user"
          ];
          edit = [
            "admin"
            "user"
          ];
        };
      in
      mkKC {
        attribute = [
          {
            name = "username";
            display_name = "$${username}";
            inherit permissions;
            required_for_roles = [ "user" ];
            validator = [
              {
                name = "length";
                config = {
                  min = 3;
                  max = 255;
                };
              }
              { name = "username-prohibited-characters"; }
              { name = "up-username-not-idn-homograph"; }
            ];
          }
          {
            name = "email";
            display_name = "$${email}";
            inherit permissions;
            required_for_roles = [ "user" ];
            validator = [
              { name = "email"; }
              {
                name = "length";
                config = {
                  max = 255;
                };
              }
            ];
          }
          {
            name = "firstName";
            display_name = "$${firstName}";
            inherit permissions;
            validator = [
              {
                name = "length";
                config = {
                  max = 255;
                };
              }
              { name = "person-name-prohibited-characters"; }
            ];
          }
          {
            name = "lastName";
            display_name = "$${lastName}";
            inherit permissions;
            validator = [
              {
                name = "length";
                config = {
                  max = 255;
                };
              }
              { name = "person-name-prohibited-characters"; }
            ];
          }
        ];

        group = [
          {
            name = "user-metadata";
            display_header = "User metadata";
            display_description = "Attributes, which refer to user metadata";
          }
        ];
      };

    resource.keycloak_role.admin = mkKC {
      name = "admin";
      description = "$${role_admin}";
    };

    resource.keycloak_openid_client.kubernetes = mkKC {
      client_id = "kubernetes";
      name = "Kubernetes";
      description = "kubectl/kubelogin OIDC authentication against the hetzkube cluster API server.";

      valid_redirect_uris = [
        # Kubelogin runs some local webserver here when setting up OIDC tokens
        "http://localhost:8000"
      ];

      standard_flow_enabled = true;
      direct_access_grants_enabled = false;
      service_accounts_enabled = false;
      access_type = "PUBLIC";

      # Presentation: show up in the Account Console's Applications list
      # (and stay listed even before a user's first kubectl login), with a
      # consent screen + icon like any other real-world SSO client instead
      # of silently minting tokens. Account Console only ever renders
      # `logoUri` (client.attributes.logoUri, see Keycloak's
      # AccountRestService#modelToRepresentation) once a UserConsentModel
      # exists for that user+client, hence consent_required here too.
      always_display_in_console = true;
      consent_required = true;
      display_on_consent_screen = true;
      consent_screen_text = "access the Kubernetes cluster API on your behalf";
      extra_config = {
        logoUri = "https://raw.githubusercontent.com/cncf/artwork/main/projects/kubernetes/icon/color/kubernetes-icon-color.png";
      };
    };

    resource.keycloak_openid_user_realm_role_protocol_mapper.kubernetes = mkKC {
      client_id = config.resource.keycloak_openid_client.kubernetes "id";
      name = "groups";

      claim_name = "groups";
      multivalued = true;
    };

    resource.keycloak_openid_client.headlamp =
      let
        host = "headlamp.lillecarl.com";
      in
      mkKC {
        client_id = "headlamp";
        name = "Headlamp";
        description = "Web UI for browsing and managing the hetzkube cluster.";

        valid_redirect_uris = [ "https://${host}/oidc-callback" ];
        base_url = "https://${host}";
        root_url = "https://${host}";
        web_origins = [ "https://${host}" ];

        standard_flow_enabled = true;
        direct_access_grants_enabled = false;
        service_accounts_enabled = false;
        access_type = "PUBLIC";
        access_token_lifespan = "28800"; # 8 hour tokens

        always_display_in_console = true;
        consent_required = true;
        display_on_consent_screen = true;
        consent_screen_text = "view and manage Kubernetes resources on your behalf";
        extra_config = {
          logoUri = "https://raw.githubusercontent.com/cncf/artwork/main/projects/headlamp/icon/color/headlamp-icon-color.png";
        };
      };

    resource.keycloak_openid_user_realm_role_protocol_mapper.headlamp = mkKC {
      client_id = config.resource.keycloak_openid_client.headlamp "id";
      name = "groups";

      claim_name = "groups";
      multivalued = true;
    };

    # Add kubernetes audience for headlamp since it passes it's oidc token onto Kubernetes
    resource.keycloak_openid_audience_protocol_mapper.headlamp_kubernetes_audience = mkKC {
      client_id = config.resource.keycloak_openid_client.headlamp "id";
      name = "Kubernetes Audience";
      included_client_audience = resource.keycloak_openid_client.kubernetes.client_id;
      add_to_id_token = true;
    };

    resource.keycloak_openid_client.grafana =
      let
        host = "grafana.lillecarl.com";
      in
      mkKC {
        client_id = "grafana";
        name = "Grafana";
        description = "Dashboards and metrics/logs exploration for the hetzkube cluster.";

        valid_redirect_uris = [ "https://${host}/login/generic_oauth" ];
        base_url = "https://${host}";
        root_url = "https://${host}";
        web_origins = [ "https://${host}" ];

        standard_flow_enabled = true;
        direct_access_grants_enabled = true;
        service_accounts_enabled = false;
        access_type = "PUBLIC";
        access_token_lifespan = "28800"; # 8 hour tokens

        always_display_in_console = true;
        consent_required = true;
        display_on_consent_screen = true;
        consent_screen_text = "view your profile and role for dashboard access";
        extra_config = {
          logoUri = "https://raw.githubusercontent.com/grafana/grafana/main/public/img/grafana_icon.svg";
        };
      };

    resource.keycloak_openid_group_membership_protocol_mapper.grafana = mkKC {
      client_id = resource.keycloak_openid_client.grafana "id";
      name = "Group Membership";

      claim_name = "groups";
      full_path = false;
    };

    resource.keycloak_openid_client.argocd =
      let
        host = "argocd.lillecarl.com";
      in
      mkKC {
        client_id = "argocd";
        name = "ArgoCD";
        description = "GitOps continuous delivery for the hetzkube cluster.";

        valid_redirect_uris = [ "https://${host}/auth/callback" ];
        base_url = "https://${host}";
        root_url = "https://${host}";
        web_origins = [ "https://${host}" ];

        standard_flow_enabled = true;
        direct_access_grants_enabled = false;
        service_accounts_enabled = false;
        access_type = "PUBLIC";
        access_token_lifespan = "28800"; # 8 hour tokens

        always_display_in_console = true;
        consent_required = true;
        display_on_consent_screen = true;
        consent_screen_text = "view your profile and role for GitOps sync/deploy access";
        extra_config = {
          logoUri = "https://raw.githubusercontent.com/cncf/artwork/main/projects/argo/icon/color/argo-icon-color.png";
        };
      };

    resource.keycloak_openid_user_realm_role_protocol_mapper.argocd = mkKC {
      client_id = config.resource.keycloak_openid_client.argocd "id";
      name = "groups";

      claim_name = "groups";
      multivalued = true;
    };

    resource.keycloak_openid_client.pgadmin =
      let
        host = "pgadmin.lillecarl.com";
      in
      mkKC {
        client_id = "pgadmin";
        name = "pgAdmin4";
        description = "Web-based administration for the cluster's PostgreSQL databases.";

        valid_redirect_uris = [
          "https://${host}/oauth2/authorize"
        ];
        base_url = "https://${host}";
        root_url = "https://${host}";
        admin_url = "https://${host}";
        web_origins = [ "https://${host}" ];

        standard_flow_enabled = true;
        direct_access_grants_enabled = false;
        service_accounts_enabled = false;
        access_type = "PUBLIC";

        always_display_in_console = true;
        consent_required = true;
        display_on_consent_screen = true;
        consent_screen_text = "view your profile for database administration access";
        extra_config = {
          logoUri = "https://raw.githubusercontent.com/pgadmin-org/pgadmin4/master/web/pgadmin/static/img/logo-256.png";
        };
      };
  };
}
