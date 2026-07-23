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

      package = pkgs.stdenv.mkDerivation {
        pname = "kubernetes-mixin";
        version = cfg.version;

        inherit src;

        nativeBuildInputs = [ pkgs.go-jsonnet ];

        buildPhase = ''
          ln -s ${vendor} vendor

          jsonnet -J vendor -e '(import "mixin.libsonnet").prometheusAlerts' > prometheus_alerts.json
          jsonnet -J vendor -e '(import "mixin.libsonnet").prometheusRules' > prometheus_rules.json
          mkdir -p dashboards_out
          jsonnet -J vendor -m dashboards_out lib/dashboards.jsonnet
        '';

        installPhase = ''
          mkdir -p $out/dashboards
          cp prometheus_alerts.json $out/
          cp prometheus_rules.json $out/
          cp dashboards_out/*.json $out/dashboards/
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
    in
    lib.mkIf cfg.enable {
      kubernetes.resources.none.Namespace.${cfg.namespace} = { };
      kubernetes.resources.${cfg.namespace} = {
        VMRule.kubernetes-mixin-alerts = {
          metadata.labels.role = "metrics";
          spec = {
            groups = normalizeGroups (lib.importJSON "${package}/prometheus_alerts.json").groups;
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
                json = builtins.readFile path;
              };
            };
          }))
          lib.listToAttrs
        ];
      };
    };
}
