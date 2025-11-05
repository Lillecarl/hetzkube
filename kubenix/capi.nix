{
  config,
  pkgs,
  lib,
  ...
}:
let
  moduleName = "capi";
  clusterName = config.clusterName;
  cfg = config.${moduleName};

  # Commands to run before kubeadm that initializes the node properly
  # ClusterAPI wants a list but we don't want a list
  preKubeadmCommands = [
    ''
      #! /usr/bin/env bash
      set -x
      export PATH=/run/current-system/sw/bin:$PATH
      # Clone latest config
      git clone https://github.com/lillecarl/hetzkube.git /etc/hetzkube
      # Get node info
      nix run --file /etc/hetzkube pkgs.hetzInfo
      # Rebuild with new config, TODO: split image and prod configs
      nixos-rebuild switch --file /etc/hetzkube/ --attr nixosConfigurations.image-$(nix eval --raw --impure --expr builtins.currentSystem)
    ''
  ];

  # A more chill contol-plane taint, let all nodes work!
  cpTaints = [
    {
      effect = "PreferNoSchedule";
      key = "node-role.kubernetes.io/control-plane";
    }
  ];
  # ImageVolume for CNPG, KubeletPSI because it's cool
  featureGates = "ImageVolume=true,KubeletPSI=true";
  nodeRegistration = {
    kubeletExtraArgs = {
      "feature-gates" = featureGates;
      "fail-swap-on" = "false";
      "cgroup-driver" = "systemd";
      "cloud-provider" = "external";
      "resolv-conf" = "/etc/kubernetes/resolv.conf";
    };
    ignorePreflightErrors = [
      "Swap"
      # TODO: Remove this when Kubeadm isn't bugged anymore
      "HTTPProxyCIDR"
    ];
  };
  dc = "hel1";
in
{
  options.${moduleName} = {
    enable = lib.mkEnableOption "capi";
    controlPlaneHost = lib.mkOption {
      type = lib.types.str;
      description = "name of your cluster";
    };
  };
  config = lib.mkIf cfg.enable {
    kubernetes.resources.none.Namespace.${clusterName} = { };
    kubernetes.resources.${clusterName} = {
      # hcloud token, templated from SOPS with kluctl
      Secret.hetzner.stringData.hcloud = "{{ hctoken }}";

      # Contol plane
      KubeadmControlPlane."${clusterName}-control-plane".spec = {
        kubeadmConfigSpec = {
          clusterConfiguration = {
            apiServer.extraArgs = {
              feature-gates = featureGates;
              oidc-issuer-url = "https://keycloak.lillecarl.com/realms/master";
              oidc-client-id = "kubernetes";
              oidc-username-claim = "sub";
              oidc-groups-claim = "groups";
            };
            controllerManager.extraArgs.feature-gates = featureGates;
            scheduler.extraArgs.feature-gates = featureGates;
            etcd = { };
          };
          inherit preKubeadmCommands;
          initConfiguration = {
            skipPhases = [
              "addon/kube-proxy" # Replaced by Cilium
              "addon/coredns" # Deployed by us
            ];
            nodeRegistration = nodeRegistration // {
              taints = cpTaints;
            };
          };
          joinConfiguration = {
            nodeRegistration = nodeRegistration // {
              taints = cpTaints;
            };
          };
          postKubeadmCommands = [
            ''
              #! /usr/bin/env bash
              export KUBECONFIG=/etc/kubernetes/admin.conf
              # This only exists on the image
              export SOPS_AGE_KEY_FILE=/etc/nodekey
              # Check if cluster has been previously initialized, if not run init deployment script
              kubectl --namespace kube-public get configmaps initialized || nix run --file /etc/hetzkube init.deploymentScript -- --yes --no-wait
              # Install admin config to node
              install -D --mode=0600 --owner=hetzkube /etc/kubernetes/admin.conf /home/hetzkube/.kube/config
            ''
          ];
        };
        machineTemplate = {
          infrastructureRef = {
            apiVersion = "infrastructure.cluster.x-k8s.io/v1beta1";
            kind = "HCloudMachineTemplate";
            name = "${clusterName}-control-plane";
          };
        };
        replicas = 1;
        version = "v${pkgs.kubernetes.version}"; # beware to make images!
      };
      Cluster.${clusterName} = {
        metadata.labels.clusterName = clusterName;
        spec = {
          clusterNetwork = {
            pods.cidrBlocks = [
              "10.133.7.0/16" # 65536
              "fdce:9c4d:abcd::/48" # Very big
            ];
            services.cidrBlocks = [
              "10.133.8.0/16" # 65536
              "fdce:9c4d:dcba::/112" # 65536
            ];
          };
          controlPlaneRef = {
            apiVersion = "controlplane.cluster.x-k8s.io/v1beta1";
            kind = "KubeadmControlPlane";
            name = "${clusterName}-control-plane";
          };
          infrastructureRef = {
            apiVersion = "infrastructure.cluster.x-k8s.io/v1beta1";
            kind = "HetznerCluster";
            name = clusterName;
          };
        };
      };
      HetznerCluster.${clusterName}.spec = {
        controlPlaneRegions = [ dc ];
        # No LB for control-plane
        controlPlaneEndpoint.host = cfg.controlPlaneHost;
        controlPlaneLoadBalancer.enabled = false;
        controlPlaneEndpoint.port = 6443;
        # No private networking
        hcloudNetwork.enabled = false;
        hcloudPlacementGroups = {
          _namedlist = true;
          control-plane.type = "spread";
          workers.type = "spread";
        };
        hetznerSecretRef = {
          key.hcloudToken = "hcloud";
          name = "hetzner";
        };
        # We already have SSH keys provisioned with Nix, CAPI doesn't need them.
        # sshKeys = {
        #   hcloud = [ { name = "hetznerKeyName"; } ];
        # };
      };
      MachineHealthCheck."${clusterName}-control-plane-unhealthy-5m".spec = {
        inherit clusterName;
        maxUnhealthy = "100%";
        nodeStartupTimeout = "15m";
        remediationTemplate = {
          apiVersion = "infrastructure.cluster.x-k8s.io/v1beta1";
          kind = "HCloudRemediationTemplate";
          name = "control-plane-remediation-request";
        };
        selector = {
          matchLabels = {
            "cluster.x-k8s.io/control-plane" = "";
          };
        };
        unhealthyConditions = [
          {
            status = "Unknown";
            timeout = "180s";
            type = "Ready";
          }
          {
            status = "False";
            timeout = "180s";
            type = "Ready";
          }
        ];
      };
      HCloudMachineTemplate."${clusterName}-control-plane".spec.template.spec = {
        imageName = "2505-x86";
        placementGroupName = "control-plane";
        type = "cx23";
      };
      HCloudRemediationTemplate."control-plane-remediation-request".spec.template.spec = {
        strategy = {
          retryLimit = 1;
          timeout = "180s";
          type = "Reboot";
        };
      };

      # Worker config
      #
      # Share Kubeadm configuration between different worker configurations
      KubeadmConfigTemplate."${clusterName}-workers".spec.template.spec = {
        joinConfiguration.nodeRegistration = nodeRegistration;
        inherit preKubeadmCommands;
      };
      HCloudRemediationTemplate."worker-remediation-request".spec.template.spec.strategy = {
        retryLimit = 1;
        timeout = "180s";
        type = "Reboot";
      };

      # x86 pool
      MachineDeployment."${clusterName}-workers-x86" = {
        metadata.labels.nodepool = "${clusterName}-workers-x86";
        spec = {
          inherit clusterName;
          replicas = 0;
          selector = { };
          template = {
            metadata.labels.nodepool = "${clusterName}-workers-x86";
            spec = {
              bootstrap = {
                configRef = {
                  apiVersion = "bootstrap.cluster.x-k8s.io/v1beta1";
                  kind = "KubeadmConfigTemplate";
                  name = "${clusterName}-workers";
                };
              };
              inherit clusterName;
              failureDomain = dc;
              infrastructureRef = {
                apiVersion = "infrastructure.cluster.x-k8s.io/v1beta1";
                kind = "HCloudMachineTemplate";
                name = "${clusterName}-workers-x86";
              };
              version = "v${pkgs.kubernetes.version}"; # beware to make images!
            };
          };
        };
      };
      MachineHealthCheck."${clusterName}-workers-x86-unhealthy-5m".spec = {
        inherit clusterName;
        maxUnhealthy = "100%";
        nodeStartupTimeout = "10m";
        remediationTemplate = {
          apiVersion = "infrastructure.cluster.x-k8s.io/v1beta1";
          kind = "HCloudRemediationTemplate";
          name = "worker-remediation-request";
        };
        selector = {
          matchLabels = {
            nodepool = "${clusterName}-workers-x86";
          };
        };
        unhealthyConditions = [
          {
            status = "Unknown";
            timeout = "180s";
            type = "Ready";
          }
          {
            status = "False";
            timeout = "180s";
            type = "Ready";
          }
        ];
      };
      HCloudMachineTemplate."${clusterName}-workers-x86".spec.template.spec = {
        imageName = "2505-x86";
        placementGroupName = "workers";
        type = "cx23";
      };

      # arm64 pool
      MachineDeployment."${clusterName}-workers-arm64" = {
        metadata.labels.nodepool = "${clusterName}-workers-arm64";
        spec = {
          inherit clusterName;
          replicas = 0;
          selector = { };
          template = {
            metadata.labels.nodepool = "${clusterName}-workers-arm64";
            spec = {
              bootstrap = {
                configRef = {
                  apiVersion = "bootstrap.cluster.x-k8s.io/v1beta1";
                  kind = "KubeadmConfigTemplate";
                  name = "${clusterName}-workers";
                };
              };
              inherit clusterName;
              failureDomain = dc;
              infrastructureRef = {
                apiVersion = "infrastructure.cluster.x-k8s.io/v1beta1";
                kind = "HCloudMachineTemplate";
                name = "${clusterName}-workers-arm64";
              };
              version = "v${pkgs.kubernetes.version}"; # beware to make images!
            };
          };
        };
      };
      MachineHealthCheck."${clusterName}-workers-arm64-unhealthy-5m".spec = {
        inherit clusterName;
        maxUnhealthy = "100%";
        nodeStartupTimeout = "10m";
        remediationTemplate = {
          apiVersion = "infrastructure.cluster.x-k8s.io/v1beta1";
          kind = "HCloudRemediationTemplate";
          name = "worker-remediation-request";
        };
        selector = {
          matchLabels = {
            nodepool = "${clusterName}-workers-arm64";
          };
        };
        unhealthyConditions = [
          {
            status = "Unknown";
            timeout = "180s";
            type = "Ready";
          }
          {
            status = "False";
            timeout = "180s";
            type = "Ready";
          }
        ];
      };
      HCloudMachineTemplate."${clusterName}-workers-arm64".spec.template.spec = {
        imageName = "2505-arm";
        placementGroupName = "workers";
        type = "cx23";
      };
    };
    kubernetes.apiMappings = {
      Cluster = "cluster.x-k8s.io/v1beta1";
      HCloudMachineTemplate = "infrastructure.cluster.x-k8s.io/v1beta1";
      HCloudRemediationTemplate = "infrastructure.cluster.x-k8s.io/v1beta1";
      HetznerCluster = "infrastructure.cluster.x-k8s.io/v1beta1";
      KubeadmConfigTemplate = "bootstrap.cluster.x-k8s.io/v1beta1";
      KubeadmControlPlane = "controlplane.cluster.x-k8s.io/v1beta1";
      MachineDeployment = "cluster.x-k8s.io/v1beta1";
      MachineHealthCheck = "cluster.x-k8s.io/v1beta1";
    };
    kubernetes.namespacedMappings = {
      Cluster = true;
      HCloudMachineTemplate = true;
      HCloudRemediationTemplate = true;
      HetznerCluster = true;
      KubeadmConfigTemplate = true;
      KubeadmControlPlane = true;
      MachineDeployment = true;
      MachineHealthCheck = true;
    };
  };
}
