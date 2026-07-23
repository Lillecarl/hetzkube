# What to do?

## How to use this file

Take an item, sorted by priority, investigate and fix. Move task to completed with a short action description
Priority is high to low where high numbers goes first.

# TODO

## P90 KubeVersionMismatch
Investigate why KubeVersionMismatch is firing, which components are mismatched?
If it's an easy fix, fix it. Else move this to completed and write a new task about what to fix.

## P20 Make VictoriaMetrics datasource default for kubernetes-mixin?
Try to override kubernetes-mixin to render everything on victoriametrics datasources instead of prometheus
If possible, make it configureable with an enum option for prometheus and victoriametrics
If not possible, mark as completed with a failure desription.

## P15 disable KubeCPUOvercommit
This is a lab cluster, we are always overcommited

## P14 disable KubeMemoryOvercommit
This is a lab cluster, we are always overcommited

## P13 disable Windows dashboards
We don't have any Windows in this cluster, disable Windows on kubernetes-mixin

## P10 Investigate if _extra_binding_args can be improved
This is a code smell, can we rearchitect it?

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
