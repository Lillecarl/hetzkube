# Updating projects
Skip "cluster critical projects" (Cilium, ClusterAPI)
```python (pseudocode)
for i in project: # note that this is sequential, one at a time
  update_src # lib.fakehash if we use a pkgs fetcher
  deploy # nix run --file . kubenix.passthru.ekn -- deploy --file . -A kubenix --push -m "..."
  monitor_rollout # use kubectl to check that everything is fine
  jj diff --git
  jj commit -m 'Updated $project from xyz to abc'
```
