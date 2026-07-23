{ config, lib, ... }:
{
  options.kube-proxy.enable = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = ''
      Whether kube-proxy is expected to be running in this cluster. This is
      purely a signal other modules gate behavior on (e.g.
      kubernetes-mixins' KubeProxyDown alert, which otherwise fires forever
      once nothing ever reports `up{job="kube-proxy"}`) -- it does not
      itself install or remove anything. `capi.nix`'s
      `initConfiguration.skipPhases` is what actually keeps kubeadm from
      installing kube-proxy, and is what this option's default reacts to.
    '';
  };

  config = lib.mkIf (config.cilium.enable && config.cilium.kubeProxyReplacement) {
    # Cilium's kube-proxy replacement means kube-proxy is never installed at
    # all (see capi.nix's skipPhases) -- force this off rather than let it
    # default independently, so the two can't drift out of sync.
    kube-proxy.enable = lib.mkForce false;
  };
}
