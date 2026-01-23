{ lib, ... }:
{
  config = {
    kyverno = {
      enable = true;
      version = "3.6.2";
      sha256 = "sha256-5nKKKWAg1JFfsUxo120SMBqKDkd9VmNzE/bB+ty1gjI=";
    };
    kubernetes.resources.none = {
      ClusterPolicy = {
        add-metallb-shared-ip = {
          spec = {
            rules = [
              {
                name = "add-allow-shared-ip-annotation";
                match.resources.kinds = [ "Service" ];
                preconditions = {
                  all = [
                    {
                      key = "{{ request.object.spec.type }}";
                      operator = "Equals";
                      value = "LoadBalancer";
                    }
                  ];
                };
                mutate.patchStrategicMerge.metadata.annotations = {
                  "metallb.io/allow-shared-ip" = "true";
                };
              }
            ];
          };
        };
        require-dualstack-services = {
          spec = {
            rules = [
              {
                name = "set-require-dualstack";
                match.resources.kinds = [ "Service" ];
                mutate.patchStrategicMerge.spec = {
                  ipFamilyPolicy = "RequireDualStack";
                  ipFamilies = [
                    "IPv4"
                    "IPv6"
                  ];
                };
              }
            ];
          };
        };
        external-dns-ttl = {
          spec.rules = [
            {
              name = "add-dns-ttl-annotation";
              match.resources.kinds = [
                "Ingress"
                "HTTPRoute"
              ];
              mutate.patchStrategicMerge.metadata.annotations = {
                "external-dns.alpha.kubernetes.io/ttl" = "60";
              };
            }
          ];
        };
      };
    };
  };
}
