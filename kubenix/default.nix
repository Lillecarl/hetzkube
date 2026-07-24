{
  pkgs,
  pkgsOff,
  easykubenix,
  nix-csi,
  args,
}:
let
  inherit (pkgs) lib;
  # "full" is the day-to-day default -- "capi" only matters when
  # bootstrapping a brand new cluster from scratch (see README.md), a
  # one-time concern, not something worth nagging about on every eval.
  stage = args.stage or "full";
in
import easykubenix {
  inherit pkgs;
  modules = [
    {
      _module.args = {
        inherit pkgsOff;
      };
    }
    ./modules
    ./capi
    ./full
    ./configuration
    "${nix-csi}/kubenix"
    {
      config = {
        kluctl.discriminator = stage;
        # Consumed by `ekn kubeapply`/`ekn validate`'s kr8s-based
        # apply_and_prune (barrier ordering + pruning), not by the real
        # kluctl binary -- ArgoCD replaced kluctl as the actual deploy
        # mechanism, but this option (defined by easykubenix's core
        # kluctl.nix) is still the generic knob that logic reads. Overrides
        # easykubenix's Namespace/CustomResourceDefinition=10-only default:
        kluctl.resourcePriority = {
          Namespace = 10;
          CustomResourceDefinition = 15;
          Secret = 20;
          # Applying a Mutating/ValidatingWebhookConfiguration registers it
          # with the apiserver immediately -- every object that lands in the
          # same (default, unlisted-kind) barrier as one of these but
          # happens to be ordered after it in that barrier's list gets
          # intercepted by a webhook whose backend may not exist yet (a
          # fresh `ekn kubeapply --target bootstrap` run, or `ekn validate`'s
          # harness, which never has one running at all). Giving these their
          # own barrier strictly after the default 100 bucket means every
          # other object is already applied before any webhook can intercept
          # anything.
          MutatingWebhookConfiguration = 200;
          ValidatingWebhookConfiguration = 200;
        };
        ekn.cacheTo = "ssh-ng://nix@pynixd.lillecarl.com:2222";
        inherit stage;
      };
    }
  ];
}
