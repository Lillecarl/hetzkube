# What to do?

## How to use this file

Take an item, sorted by priority, investigate and fix. Move task to completed with a short action description
Priority is high to low where high numbers goes first.
If the TODO list becomes empty, keep a placeholder example alive to maintain structure.

# TODO

## P85 Fix KubeVersionMismatch: kubelet lags capi.version by a minor
kubelet is sourced from `pkgs.kubernetes` in nixos/kubernetes.nix (currently
resolves to 1.35.0), while kubenix/modules/capi.nix:87 pins
`capi.version = "1.36.1"` for the control-plane/worker MachineDeployments
(apiserver/controller-manager/scheduler images). Nothing ties the two
together, so they've drifted -- confirmed live on the cluster (kubelets at
v1.35.0, control-plane pods at v1.36.1), which is exactly what
kubernetes-mixin's KubeVersionMismatch rule (buckets `kubernetes_build_info`
by major.minor `git_version`, fires if >1 bucket) detects.
Align them -- either bump nixpkgs so `pkgs.kubernetes.version` tracks 1.36.x,
or override the kubelet package version to explicitly follow
`config.capi.version` -- then roll the nodes. Once aligned, consider adding a
NixOS assertion (`config.assertions`) comparing the two so this can't
silently drift again; capi.version was deliberately pinned in a prior commit
specifically to avoid silent drift, but that only covered the control-plane
side.

## P14 disable KubeMemoryOvercommit
This is a lab cluster, we are always overcommited

## P13 disable Windows dashboards
We don't have any Windows in this cluster, disable Windows on kubernetes-mixin

# COMPLETED

## P100 kubernetes-mixin and kube-proxy
Add a kube-proxy module, initially it can just be a dummy to gate other modules behavior with. If Cilium has kubeproxyreplacement enabled kube-proxy should be forced to off.
kubernetes-mixin enables a warning about kube-proxy being down, if kube-proxy isn't enabled we shouldn't warn on it.
Resolution:
Added kubenix/modules/kube-proxy.nix with a kube-proxy.enable option. cilium.nix
forces it off when cilium.kubeProxyReplacement is set. capi.nix's
initConfiguration.skipPhases and kubernetes-mixins.nix's KubeProxyDown alert
group both gate on it now. Awaiting a control-plane deploy/re-roll to take
effect on the live cluster.

## P80 investigate where and why "yq --prettyprint" is used in the ekn deployment pipeline
We should not be using "yq" anywhere now that we have YAML built into ekn cli and registering Nix primops other than as a fallback.
Hint: What attribute set
Resolution:
The only remaining yq use is easykubenix/pkgs/renderChart.nix, and it's already
gated behind `builtins ? fromYAML11Stream` -- it only runs for plain
`nix build`/`nix eval` consumers that aren't going through ekn's worker (no
access to the fromYAML11Stream primop or ekn.lib), which is exactly the
"fallback" case the task carved out. Every real ekn-pipeline path
(importyaml.nix/helm.nix) already uses ekn's own `_yamlToJson` CLI subcommand
instead of yq. No further change needed.

## P1337 finished demotask
Do nothing but move this to completed
Resolution:
Moved to completed

## P90 KubeVersionMismatch
Investigate why KubeVersionMismatch is firing, which components are mismatched?
If it's an easy fix, fix it. Else move this to completed and write a new task about what to fix.
Resolution:
kubernetes-mixin's rule buckets `kubernetes_build_info` by major.minor
`git_version` and fires when more than one bucket exists cluster-wide.
Confirmed live: kubelets on both nodes report v1.35.0 (from
`pkgs.kubernetes` in nixos/kubernetes.nix), while kube-apiserver/
controller-manager/scheduler pods run v1.36.1 (from
kubenix/modules/capi.nix's `capi.version` option, deliberately pinned
independently of nixpkgs by a prior commit to stop nixpkgs bumps from
silently rolling the control plane). That pin only covers the control-plane
side -- the kubelet still floats with whatever nixpkgs happens to package --
so the two silently drifted apart. Not a one-line fix (requires either a
nixpkgs bump or a version override plus a node roll), so filed as P85 above
with the specific remediation.

## P20 Make VictoriaMetrics datasource default for kubernetes-mixin?
Try to override kubernetes-mixin to render everything on victoriametrics datasources instead of prometheus
If possible, make it configureable with an enum option for prometheus and victoriametrics
If not possible, mark as completed with a failure desription.
Resolution:
Possible. Upstream hardcodes the Grafana datasource plugin type as the
literal string "prometheus" in every dashboard's rendered JSON (the
`datasource` template variable's plugin-type filter, and every panel
target's `datasource.type`) with no `_config` knob reaching it, so
kubenix/modules/kubernetes-mixins.nix now post-processes the *rendered*
dashboard JSON instead of patching upstream's jsonnet/vendored-grafonnet
source (source-patching would be brittle against upstream reformatting; the
rendered JSON schema is stable). Added `kubernetes-mixins.datasourceType`
(enum "prometheus" | "victoriametrics", default "victoriametrics") and a
`patchDatasourceType` recursive walker that descends into both attrsets and
JSON-array-turned-Nix-lists (plain `lib.mapAttrsRecursive` doesn't reach into
lists, which is where nearly everything in a Grafana dashboard lives --
panels, targets, templating.list), rewriting only two structurally-anchored
spots: a `datasource = { type = "prometheus"; ... }` object, and a
datasource-picker variable's own `query` field (guarded on a sibling
`type = "datasource"` so real PromQL variables aren't touched). Verified with
`pynix ekn diff -f . -A kubenix`: only the 22 GrafanaDashboard files with a
datasource reference changed, VMRule alerts/rules are untouched, and every
added `datasource` block is either the correct
`victoriametrics-metrics-datasource` (486 occurrences) or an unrelated
Grafana built-in `-- Mixed --` ref correctly left alone (249).
Default "victoriametrics" targets kubenix/configuration/grafana.nix's
`vmsingle-vm` datasource (the native VictoriaMetrics plugin); "prometheus"
keeps upstream's default, matching `vmsingle-prom`.

## P15 disable KubeCPUOvercommit
This is a lab cluster, we are always overcommited
Resolution:
`kubernetes-resources` (the alert group KubeCPUOvercommit lives in) also
holds alerts we still want (KubeMemoryOvercommit, the quota alerts,
CPUThrottlingHigh), so a whole-group drop like dropKubeProxyAlerts wasn't
appropriate here. Added `kubernetes-mixins.disabledAlerts` (list of alert
names) and a `dropNamedAlerts` filter that removes matching rules from
whichever group they're in and drops any group left with an empty rules
list; set in kubenix/configuration/victoriametrics.nix to
`[ "KubeCPUOvercommit" ]`. Verified with `pynix ekn diff -f . -A kubenix`:
only the kubernetes-mixin-alerts VMRule changed, and the diff is exactly the
one KubeCPUOvercommit rule removed -- KubeMemoryOvercommit and every other
rule in the group untouched.
