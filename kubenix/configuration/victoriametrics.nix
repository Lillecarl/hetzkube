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
          version = "0.68.5";
        };
        metrics = {
          enable = true;
          inherit namespace;
        };
        logs = {
          enable = true;
          inherit namespace;
        };
      };
      node-exporter = {
        enable = true;
        inherit namespace;
      };
      kube-state-metrics = {
        enable = true;
        version = "2.18.0";
        inherit namespace;
      };
      grafana-operator = {
        enable = true;
      };
      kubernetes-mixins = {
        enable = true;
      };
    };
}
