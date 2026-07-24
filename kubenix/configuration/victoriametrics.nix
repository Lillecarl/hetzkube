{ config, lib, ... }:
{
  config =
    let
      namespace = "observability";
    in
    {
      victoriametrics = {
        enable = true;
        operator = {
          enable = true;
          version = "0.73.1";
        };
        metrics = {
          enable = true;
          inherit namespace;
          externalHostname = "vmalert-metrics.lillecarl.com";
        };
        logs = {
          enable = true;
          inherit namespace;
          externalHostname = "vmalert-logs.lillecarl.com";
        };
        alertmanager = {
          enable = true;
          telegram.chatId = 8507658503;
        };
      };
      node-exporter = {
        enable = true;
        inherit namespace;
      };
      kube-state-metrics = {
        enable = true;
        version = "2.19.1";
        inherit namespace;
      };
      grafana-operator = {
        enable = true;
      };
      kubernetes-mixins = {
        enable = true;
        # This is a lab cluster, we are always overcommitted -- KubeCPUOvercommit
        # would otherwise fire permanently for a condition that's normal here.
        disabledAlerts = [ "KubeCPUOvercommit" ];
      };
    };
}
