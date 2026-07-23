{
  config,
  ...
}:
{
  kluctl = {
    # ArgoCD itself (and the Application CRs that self-manage it) has its own
    # deployment path: `ekn kubeapply --target bootstrap` applies it once
    # directly, then ArgoCD's "bootstrap" Application reconciles itself from
    # then on. Don't also apply it via kluctl.
    #
    # "everything" joins it here in the same change that flips both
    # Applications' syncPolicy to automated (gitops.nix) -- the rollout
    # plan's diff-verification step confirmed ArgoCD reconciling
    # "everything" is a no-op against the kluctl-managed cluster, so this is
    # the actual cutover: kluctl and ArgoCD must not both actively manage
    # the same objects (prune wars, drift resets), so this can't lag behind
    # the syncPolicy change by even one deploy.
    excludeGitopsTargets = [
      "bootstrap"
      "everything"
    ];
    # Add SOPS secrets
    deployment.vars = [ { file = "secrets/all.yaml"; } ];
    files."secrets/all.yaml" = builtins.readFile ../../secrets/all.yaml;
    # Disable templating for default resource project
    files."default/.templateignore" = "*";
    files."prio-10/.templateignore" = "*";
    files."prio-15/.templateignore" = "*";
    # Put priorities on resources, this also excludes the from the templateignore above
    resourcePriority = {
      Namespace = 10;
      CustomResourceDefinition = 15;
      Secret = 20;
      # Applying a Mutating/ValidatingWebhookConfiguration registers it with
      # the apiserver immediately -- every object that lands in the same
      # (default, unlisted-kind) barrier as one of these but happens to be
      # ordered after it in that barrier's list gets intercepted by a
      # webhook whose backend may not exist yet (a fresh `ekn kubeapply
      # --target bootstrap` run, or ekn validate's harness, which never has
      # one running at all). Giving these their own barrier strictly after
      # the default 100 bucket means every other object is already applied
      # before any webhook can intercept anything.
      MutatingWebhookConfiguration = 200;
      ValidatingWebhookConfiguration = 200;
    };
    preDeployScript = # bash
      ''
        expected_context="hetzkube"
        current_context=$(kubectl config current-context)

        if [[ "$current_context" != *"$expected_context" ]]; then
            echo "Warning: Current context is $current_context, not *$expected_context" >&2
            read -rp "Continue anyway? [y/N] " confirm
            if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
                echo "Aborted." >&2
                exit 1
            fi
        fi

        nix copy \
          --substitute-on-destination \
          --no-check-sigs \
          --to ssh-ng://nix@pynixd.lillecarl.com:2222 \
          ${config.kluctl.projectDir} \
          -v || true
      '';

  };
}
