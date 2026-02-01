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
  };
  config =
    let
      src = builtins.fetchTree {
        type = "github";
        owner = "kubernetes-monitoring";
        repo = "kubernetes-mixin";
        ref = "version-1.4.2";
      };
      vendor = pkgs.stdenv.mkDerivation {
        name = "kubernetes-mixin-vendor";

        inherit src;

        nativeBuildInputs = with pkgs; [
          jsonnet-bundler
          git
          cacert
        ];

        buildPhase = ''
          cp $src/jsonnetfile.json jsonnetfile.json
          cp $src/jsonnetfile.lock.json jsonnetfile.lock.json

          export HOME=$TMPDIR
          jb install
        '';

        installPhase = ''
          mv vendor $out
        '';

        outputHashMode = "recursive";
        outputHash = "sha256-wO7fVh46S/dCa0dbYptNR6jM3iy4o6V7WvhhH/lbQUw=";
      };

      package = pkgs.stdenv.mkDerivation {
        pname = "kubernetes-mixin";
        version = "unstable";

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
    in
    lib.mkIf cfg.enable {
      kubernetes.resources.none.Namespace.${cfg.namespace} = { };
      kubernetes.resources.${cfg.namespace} = {
        VMRule.kubernetes-mixin-alerts = {
          metadata.labels.role = "metrics";
          spec = {
            inherit (lib.importJSON "${package}/prometheus_alerts.json") groups;
          };
        };
        VMRule.kubernetes-mixin-rules = {
          metadata.labels.role = "metrics";
          spec = {
            inherit (lib.importJSON "${package}/prometheus_rules.json") groups;
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
