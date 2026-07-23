{
  config,
  lib,
  ...
}:
let
  moduleName = "cilium";
  cfg = config.${moduleName};
in
{
  options.${moduleName} = {
    enable = lib.mkEnableOption moduleName;
    # You'll have to re-roll Cilium pods manually when changing this.
    policyAuditMode = lib.mkEnableOption "policy-audit-mode";
    version = lib.mkOption {
      type = lib.types.str;
    };
    gatewayAPI = {
      enable = (lib.mkEnableOption "gateway api") // {
        default = true;
      };
      defaultListener = {
        enable = (lib.mkEnableOption "default listener") // {
          default = true;
        };
        issuerRef = {
          name = lib.mkOption {
            type = lib.types.nonEmptyStr;
          };
          kind = lib.mkOption {
            type = lib.types.nonEmptyStr;
            default = "ClusterIssuer";
          };
        };
        dnsNames = lib.mkOption {
          description = "Domains configured for default listener";
          type = lib.types.listOf lib.types.nonEmptyStr;
        };
        annotations = lib.mkOption {
          type = lib.types.attrsOf lib.types.str;
          default = { };
        };
      };
    };
    helmValues = lib.mkOption {
      type = lib.types.anything;
      default = { };
    };
  };
  config =
    let
      src = builtins.fetchTree {
        type = "github";
        owner = "cilium";
        repo = "cilium";
        ref = "v${cfg.version}";
      };
    in
    lib.mkMerge [
      (lib.mkIf (cfg.enable && cfg.gatewayAPI.enable) {
        cert-manager.enable = true;
        # Configure GatewayAPI version
        gateway-api.enable = true;
        gateway-api.version =
          lib.mkDefault
            {
              "1.16" = "1.1.0";
              "1.17" = "1.2.0";
              "1.18" = "1.2.0";
              "1.19" = "1.3.0";
            }
            .${lib.versions.majorMinor cfg.version};
        # Create the GatewayClass for Cilium
        kubernetes.resources.kube-system =
          lib.mkIf (cfg.gatewayAPI.enable && cfg.gatewayAPI.defaultListener.enable)
            {
              CiliumGatewayClassConfig.cilium = {
                spec = {
                  service = {
                    ipFamilyPolicy = "RequireDualStack";
                    ipFamilies = [
                      "IPv4"
                      "IPv6"
                    ];
                  };
                };
              };
              GatewayClass.cilium = {
                spec = {
                  controllerName = "io.cilium/gateway-controller";
                  parametersRef = {
                    group = "cilium.io";
                    kind = "CiliumGatewayClassConfig";
                    name = "cilium";
                  };
                };
              };
              Gateway.default = {
                metadata.annotations = cfg.gatewayAPI.defaultListener.annotations;
                spec = {
                  gatewayClassName = "cilium";
                  infrastructure.annotations = cfg.gatewayAPI.defaultListener.annotations;
                  listeners = [
                    {
                      name = "https";
                      protocol = "HTTPS";
                      port = 443;
                      allowedRoutes.namespaces.from = "All";
                      tls = {
                        mode = "Terminate";
                        certificateRefs = [
                          {
                            name = "default-cert";
                            kind = "Secret";
                          }
                        ];
                      };
                    }
                    {
                      name = "http";
                      protocol = "HTTP";
                      port = 80;
                      allowedRoutes.namespaces.from = "All";
                    }
                  ];
                };
              };
              Certificate.default-cert = {
                spec = {
                  secretName = "default-cert";
                  inherit (cfg.gatewayAPI.defaultListener) dnsNames issuerRef;
                };
              };
              HTTPRoute.http-redirect = {
                spec = {
                  parentRefs = [
                    {
                      # Must match the Gateway object's own metadata.name
                      # ("default", see gatewayAPI.defaultListener above) --
                      # not its gatewayClassName ("cilium"). This was wrong
                      # for the lifetime of this object: with no Gateway
                      # actually named "cilium", the route never resolved a
                      # parent at all (status was empty) and this
                      # HTTP->HTTPS redirect never actually attached/worked.
                      name = "default";
                      namespace = "kube-system";
                      sectionName = "http";
                    }
                  ];
                  rules = [
                    {
                      filters = [
                        {
                          type = "RequestRedirect";
                          requestRedirect = {
                            scheme = "https";
                            statusCode = 301;
                          };
                        }
                      ];
                      # Explicit catch-all match -- Gateway API defaults this
                      # in when a rule omits `matches` entirely, which is
                      # exactly the diff ArgoCD kept flagging as OutOfSync.
                      matches = [
                        {
                          path = {
                            type = "PathPrefix";
                            value = "/";
                          };
                        }
                      ];
                    }
                  ];
                };
              };
            };
      })
      (lib.mkIf cfg.enable {
        # Disables enforcing policies
        kubernetes.resources.kube-system.ConfigMap.cilium-config.data.policy-audit-mode =
          lib.boolToString cfg.policyAuditMode;

        kubernetes.resources.kube-system = {
          # Kubernetes annotations are map[string]string -- a Nix bool here
          # serializes as a JSON boolean, which client-side apply/merge-patch
          # (kluctl) tolerates silently but real server-side apply's
          # structured-merge-diff rejects with a 500 ("expected string, got
          # &value.valueUnstructured{Value:true}") while building the typed
          # patch, since it can't reconcile the value against the
          # map[string]string schema.
          Secret.cilium-ca.metadata.annotations."kluctl.io/ignore-diff" = "true";
          Secret.hubble-server-certs.metadata.annotations."kluctl.io/ignore-diff" = "true";
          Secret.hubble-relay-client-certs.metadata.annotations."kluctl.io/ignore-diff" = "true";
        };
        helm.releases.${moduleName} = {
          namespace = "kube-system";
          chart = "${src}/install/kubernetes/cilium";

          values = lib.recursiveUpdate {
            gatewayAPI = {
              enabled = cfg.gatewayAPI.enable;
              # gatewayClass.create = lib.boolToString cfg.gatewayAPI.enable;
            };
          } cfg.helmValues;
        };
        # Install Cilium CRDs with easykubenix, required so we can install network policies before
        # cilium-operator has installed them itself.
        importyaml = lib.pipe (builtins.readDir "${src}/pkg/k8s/apis/cilium.io/client/crds/v2") [
          (lib.mapAttrs' (
            filename: type: {
              name = filename;
              value.src = "${src}/pkg/k8s/apis/cilium.io/client/crds/v2/${filename}";
            }
          ))
        ];
      })
      {
        kubernetes.apiMappings = {
          CiliumCIDRGroup = "cilium.io/v2";
          CiliumClusterwideNetworkPolicy = "cilium.io/v2";
          CiliumEndpoint = "cilium.io/v2";
          CiliumGatewayClassConfig = "cilium.io/v2alpha1";
          CiliumIdentity = "cilium.io/v2";
          CiliumL2AnnouncementPolicy = "cilium.io/v2alpha1";
          CiliumLoadBalancerIPPool = "cilium.io/v2";
          CiliumNetworkPolicy = "cilium.io/v2";
          CiliumNode = "cilium.io/v2";
          CiliumNodeConfig = "cilium.io/v2";
          CiliumPodIPPool = "cilium.io/v2alpha1";

          GatewayClass = "gateway.networking.k8s.io/v1";
          Gateway = "gateway.networking.k8s.io/v1";
          GRPCRoute = "gateway.networking.k8s.io/v1";
          HTTPRoute = "gateway.networking.k8s.io/v1";
          ReferenceGrant = "gateway.networking.k8s.io/v1beta1";
        };
        kubernetes.namespacedMappings = {
          CiliumCIDRGroup = false;
          CiliumClusterwideNetworkPolicy = false;
          CiliumEndpoint = true;
          CiliumGatewayClassConfig = true;
          CiliumIdentity = false;
          CiliumL2AnnouncementPolicy = false;
          CiliumLoadBalancerIPPool = false;
          CiliumNetworkPolicy = true;
          CiliumNode = false;
          CiliumNodeConfig = true;
          CiliumPodIPPool = false;

          GatewayClass = false;
          Gateway = true;
          GRPCRoute = true;
          HTTPRoute = true;
          ReferenceGrant = true;
        };
      }
    ];
}
