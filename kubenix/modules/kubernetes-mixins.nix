{
  config,
  pkgs,
  lib,
  ...
}:
let
  moduleName = "kubernetes-mixins";
  cfg = config.${moduleName};
in
{
  options.${moduleName} = {
    enable = lib.mkEnableOption moduleName;
    namespace = lib.mkOption {
      type = lib.types.str;
      default = "observability";
    };
    version = lib.mkOption {
      type = lib.types.nonEmptyStr;
      default = "1.4.2";
    };
    jsonnetConfig = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = { };
      description = ''
        Overrides merged into the mixin's `_config` object via jsonnet's
        `+::` overlay (same mechanism upstream's own README documents for
        customizing the mixin -- see config.libsonnet in
        kubernetes-monitoring/kubernetes-mixin for every available key, e.g.
        clusterLabel, showMultiCluster, kubeJobTimeoutDuration,
        grafanaK8s.dashboardTags). Because `+::` deep-merges objects,
        overriding one leaf (e.g. `grafanaK8s.refresh`) leaves the rest of
        that nested object (e.g. `grafanaK8s.dashboardTags`) at its upstream
        default.
      '';
    };
    datasourceType = lib.mkOption {
      type = lib.types.enum [
        "prometheus"
        "victoriametrics"
      ];
      default = "victoriametrics";
      description = ''
        Which Grafana datasource plugin type the rendered dashboards' data
        source picker/panels target. Not a `_config` knob -- upstream
        hardcodes the Grafana datasource plugin type as the literal string
        `"prometheus"` in every dashboard's rendered JSON (both the
        `datasource` template variable's plugin-type filter and every panel
        target's `datasource.type`), so it can't be reached through
        `jsonnetConfig`'s `_config` overlay. This module post-processes the
        rendered dashboard JSON (see `patchDatasourceType` below) instead of
        patching upstream's jsonnet source. `"victoriametrics"` rewrites it
        to the native `victoriametrics-metrics-datasource` plugin type (see
        kubenix/configuration/grafana.nix's `vmsingle-vm` datasource);
        `"prometheus"` keeps the upstream default, matching `vmsingle-prom`
        (VictoriaMetrics exposed over its Prometheus-compatible API under a
        Grafana "prometheus"-typed datasource).
      '';
    };
  };
  config =
    let
      src = pkgs.fetchFromGitHub {
        owner = "kubernetes-monitoring";
        repo = "kubernetes-mixin";
        rev = "version-${cfg.version}";
        hash = "sha256-YrZbe4pexkyP8nAQh5vazi5o4Xagf8aqO1fDypDQqN0=";
      };

      # jsonnet-bundler's transitive dependency closure, pinned from this
      # tag's jsonnetfile.lock.json. Fetched directly with pkgs.fetchFromGitHub
      # instead of running `jb install` inside a network-accessing
      # fixed-output derivation, so bumping the mixin version can't silently
      # change what gets fetched under one opaque recursive hash -- each
      # upstream source is its own visible, individually-pinned fetch.
      grafonnet = pkgs.fetchFromGitHub {
        owner = "grafana";
        repo = "grafonnet";
        rev = "82a19822e54a0a12a51e24dbd48fcde717dc0864";
        hash = "sha256-gdxoiF9bAwybhmqWserCSnV6RGhYBZHgZ8PnK3e3RdE=";
      };
      docsonnet = pkgs.fetchFromGitHub {
        owner = "jsonnet-libs";
        repo = "docsonnet";
        rev = "6ac6c69685b8c29c54515448eaca583da2d88150";
        hash = "sha256-Uy86lIQbFjebNiAAp0dJ8rAtv16j4V4pXMPcl+llwBA=";
      };
      xtd = pkgs.fetchFromGitHub {
        owner = "jsonnet-libs";
        repo = "xtd";
        rev = "63d430b69a95741061c2f7fc9d84b1a778511d9c";
        hash = "sha256-BEzPY8veh1dFpSmla/zwbYiThQunfXlGHKrCIxS/z0o=";
      };

      # jsonnet-bundler installs each dependency at vendor/<host>/<owner>/<repo>/<subdir>
      vendor = pkgs.linkFarm "kubernetes-mixin-vendor" {
        "github.com/grafana/grafonnet/gen/grafonnet-latest" = "${grafonnet}/gen/grafonnet-latest";
        "github.com/grafana/grafonnet/gen/grafonnet-v11.1.0" = "${grafonnet}/gen/grafonnet-v11.1.0";
        "github.com/jsonnet-libs/docsonnet/doc-util" = "${docsonnet}/doc-util";
        "github.com/jsonnet-libs/xtd" = xtd;
      };

      datasourceTypeStr = {
        prometheus = "prometheus";
        victoriametrics = "victoriametrics-metrics-datasource";
      }.${cfg.datasourceType};

      # Upstream hardcodes the Grafana datasource plugin type as the literal
      # string 'prometheus' in every dashboard's rendered JSON -- both the
      # `datasource` template variable's plugin-type filter and each panel
      # target's `datasource.type` -- with no `_config` knob to reach it.
      # Rather than patching upstream's jsonnet source (brittle: depends on
      # exact source formatting, and needs forking the vendored grafonnet
      # query builder too), walk the *rendered* dashboard JSON and rewrite
      # it there, anchored on the stable Grafana dashboard schema instead of
      # jsonnet implementation details:
      #  - a `datasource = { type = "prometheus"; uid = ...; }` object
      #    (panel targets, or a variable's own datasource ref)
      #  - a datasource-picker variable's own `query` field (only when a
      #    sibling `type = "datasource"` marks the object as one)
      # Everything else (a real PromQL variable's `query`, an unrelated
      # `type` field elsewhere) is left untouched since neither anchor
      # matches it.
      patchDatasourceType =
        value:
        if lib.isAttrs value then
          let
            selfIsDatasourceVar = (value.type or null) == "datasource";
          in
          lib.mapAttrs (
            n: v:
            if n == "datasource" && lib.isAttrs v && (v.type or null) == "prometheus" then
              v // { type = datasourceTypeStr; }
            else if n == "query" && selfIsDatasourceVar && v == "prometheus" then
              datasourceTypeStr
            else
              patchDatasourceType v
          ) value
        else if lib.isList value then
          map patchDatasourceType value
        else
          value;

      # The mixin's own customization surface: everything upstream exposes
      # for tuning alerts/rules/dashboards lives behind this single `_config`
      # overlay (its README's documented way to customize the mixin without
      # forking it), so this one Nix option is what actually makes the whole
      # mixin build flexible -- rather than reimplementing config.libsonnet's
      # ~15 knobs as individual Nix options that go stale the moment upstream
      # adds/renames one.
      entrypoint = pkgs.writeText "kubernetes-mixin-entrypoint.jsonnet" ''
        local mixin = (import 'mixin.libsonnet') + { _config+:: ${builtins.toJSON cfg.jsonnetConfig} };
        {
          'prometheus_alerts.json': mixin.prometheusAlerts,
          'prometheus_rules.json': mixin.prometheusRules,
        } + {
          ['dashboards/' + name]: mixin.grafanaDashboards[name]
          for name in std.objectFields(mixin.grafanaDashboards)
        }
      '';

      package = pkgs.stdenv.mkDerivation {
        pname = "kubernetes-mixin";
        version = cfg.version;

        inherit src;

        nativeBuildInputs = [ pkgs.go-jsonnet ];

        buildPhase = ''
          ln -s ${vendor} vendor
          mkdir -p out/dashboards
          jsonnet -J vendor -J "$src" -m out ${entrypoint}
        '';

        installPhase = ''
          mkdir -p $out/dashboards
          cp out/prometheus_alerts.json $out/
          cp out/prometheus_rules.json $out/
          cp out/dashboards/*.json $out/dashboards/
        '';
      };

      # VMRule's CRD schema declares both `alert` and `record` on every rule
      # (mutually exclusive in practice), so the apiserver defaults whichever
      # one a rule doesn't set to "" -- normalize our rules the same way so
      # ArgoCD's diff doesn't perpetually see every single rule as changed.
      normalizeGroups = lib.map (
        group:
        group
        // {
          rules = lib.map (rule: {
            alert = "";
            record = "";
          } // rule) group.rules;
        }
      );

      # The mixin has no config knob to disable its KubeProxyDown alert (it
      # unconditionally warns on `absent(up{job="kube-proxy"})`) -- when
      # kube-proxy isn't expected to run at all (Cilium's eBPF replacement),
      # that target never exists and the alert fires forever. Drop the whole
      # group rather than leave a permanently-firing false alarm.
      dropKubeProxyAlerts = lib.filter (group: group.name != "kubernetes-system-kube-proxy");
    in
    lib.mkIf cfg.enable {
      kubernetes.resources.none.Namespace.${cfg.namespace} = { };
      kubernetes.resources.${cfg.namespace} = {
        VMRule.kubernetes-mixin-alerts = {
          metadata.labels.role = "metrics";
          spec = {
            groups =
              let
                groups = (lib.importJSON "${package}/prometheus_alerts.json").groups;
              in
              normalizeGroups (if config.kube-proxy.enable then groups else dropKubeProxyAlerts groups);
          };
        };
        VMRule.kubernetes-mixin-rules = {
          metadata.labels.role = "metrics";
          spec = {
            groups = normalizeGroups (lib.importJSON "${package}/prometheus_rules.json").groups;
          };
        };
        GrafanaDashboard = lib.pipe (lib.filesystem.listFilesRecursive "${package}/dashboards") [
          (lib.map (path: {
            name = builtins.unsafeDiscardStringContext (lib.removeSuffix ".json" (lib.baseNameOf path));
            value = {
              spec = {
                instanceSelector = {
                  matchLabels = {
                    dashboards = "grafana";
                  };
                };
                json = builtins.toJSON (patchDatasourceType (lib.importJSON path));
              };
            };
          }))
          lib.listToAttrs
        ];
      };
    };
}
