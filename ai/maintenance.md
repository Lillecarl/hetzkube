# Updating projects
Skip "cluster critical projects" (Cilium, ClusterAPI)
```python (pseudocode)
for i in project: # note that this is sequential, one at a time
  update_src # lib.fakehash if we use a pkgs fetcher
  deploy # nix run --file . kubenix.deploymentScript --argstr stage full -- --write-command-result=false --prune --yes
  monitor_rollout # use kubectl to check that everything is fine
  jj diff --git
  jj commit -m 'Updated $project from xyz to abc'
```
