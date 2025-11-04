# Minimal configuration for ClusterAPI
{
  config,
  pkgs,
  lib,
  inputs,
  ...
}:
{
  config = {
    environment.systemPackages = with pkgs; [
      kubernetes
      cri-tools
      cilium-cli
    ];

    # Configure containerd CRI
    virtualisation.containerd = {
      enable = true;
      settings = {
        # Use systemd cgroups, this will tell Kubernetes to do the same
        plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc.options.SystemdCgroup = true;
        # Force /opt/cni/bin as CNI folder (all CNI's expect this and put their binaries here)
        plugins."io.containerd.grpc.v1.cri".cni.bin_dir = lib.mkForce "/opt/cni/bin";
      };
    };

    # Install CNI binaries (For those who don't use an auto-installing CNI)
    system.activationScripts.cni-install = {
      text = ''
        ${lib.getExe pkgs.rsync} --mkpath --recursive ${pkgs.cni-plugins}/bin/ /opt/cni/bin/
      '';
    };

    # Disable COW on
    system.activationScripts.noCOWs.text =
      let
        dirs = [
          "/var/lib/etcd" # etcd doesn't like COW
          "/var/lib/containerd" # AI says containerd doesn't like COW
        ];
      in
      lib.concatLines (
        lib.map (
          dir: # bash
          ''
            ${lib.getExe' pkgs.coreutils "mkdir"} --parents ${dir}
            ${lib.getExe' pkgs.e2fsprogs "chattr"} -R +C ${dir}
          '') dirs
      );

    # Copy ca-certificates into /etc instead of symlinking them
    environment.etc."ssl/certs/ca-bundle.crt".enable = false;
    environment.etc."ssl/certs/ca-certificates.crt".enable = false;
    system.activationScripts.certificates = {
      text = ''
        ${lib.getExe pkgs.rsync} --mkpath --archive ${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt /etc/ssl/certs/ca-bundle.crt
        ${lib.getExe pkgs.rsync} --mkpath --archive ${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt /etc/ssl/certs/ca-certificates.crt
      '';
    };

    # Kubelet systemd unit
    # See https://github.com/kubernetes/release/blob/master/cmd/krel/templates/latest/kubeadm/10-kubeadm.conf
    systemd.services.kubelet = {
      description = "kubelet: The Kubernetes Node Agent";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];

      unitConfig = {
        # This is our own custom thing, better than imperatively enabling the service
        ConditionPathExists = "/var/lib/kubelet/config.yaml";
      };

      # Kubelet needs "mount" binary.
      path = with pkgs; [
        util-linuxMinimal
      ];

      serviceConfig = {
        EnvironmentFile = [
          "-/var/lib/kubelet/kubeadm-flags.env"
          "-/etc/sysconfig/kubelet"
        ];
        ExecStart = "${lib.getExe' pkgs.kubernetes "kubelet"} $KUBELET_KUBECONFIG_ARGS $KUBELET_CONFIG_ARGS $KUBELET_KUBEADM_ARGS $KUBELET_EXTRA_ARGS";
        Restart = "always";
        RestartSec = 1;
        RestartMaxDelaySec = 60;
        RestartSteps = 10;
      };

      environment = {
        KUBELET_KUBECONFIG_ARGS = "--bootstrap-kubeconfig=/etc/kubernetes/bootstrap-kubelet.conf --kubeconfig=/etc/kubernetes/kubelet.conf";
        KUBELET_CONFIG_ARGS = "--config=/var/lib/kubelet/config.yaml";
      };
    };

    ### Code from below is taken from clusterctl default templating stuff
    boot.kernelModules = [
      "overlay"
      "br_netfilter"
      "nf_conntrack"
    ];

    boot.kernel.sysctl = {
      # Cilium
      "net.ipv4.conf.lxc*.rp_filter" = 0;

      # Kubernetes CNI
      "net.bridge.bridge-nf-call-iptables" = 1;
      "net.bridge.bridge-nf-call-ip6tables" = 1;
      "net.ipv4.ip_forward" = 1;

      # Kubelet
      "vm.overcommit_memory" = 1;
      "kernel.panic" = 10;
      "kernel.panic_on_oops" = 1;
    };

    # Workaround for cloud-init sticking 19 DNS servers in for me
    environment.etc."kubernetes/resolv.conf".text = ''
      nameserver 1.1.1.1
      nameserver 2606:4700:4700::1111
    '';
  };
}
