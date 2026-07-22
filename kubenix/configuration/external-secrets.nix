{
  config,
  pkgs,
  lib,
  eso,
  ...
}:
{
  config = lib.mkIf (config.stage == "full") {
    external-secrets = {
      enable = true;
    };
    # The scaleway Secret is the one credential ESO needs to talk to the
    # Scaleway provider -- it used to be populated via kluctl's own
    # deployment.vars Jinja substitution ({{ SCW_ACCESS_KEY }} placeholders
    # rendered from secrets/all.yaml at kluctl-deploy time). Now that ArgoCD's
    # repo-server has a working ksops KRM-generator (see argocd.nix's
    # ksops.enable), this is sourced as a real SOPS-encrypted object instead,
    # decrypted at sync/apply time rather than template-substituted --
    # matching how the rest of the ArgoCD rollout is meant to replace kluctl.
    #
    # No special GitOps-target routing needed -- it stays on the default
    # "everything" path like the rest of the ESO stack (no ordering
    # dependency requires it to exist before external-secrets itself; ESO
    # just retries until the Secret shows up, same as any other
    # ExternalSecret). kluctl.nix's isExcludedFromKluctl now generically
    # excludes any object carrying a `sops` key regardless of target, so
    # kluctl never touches this one's raw ciphertext even while it still
    # owns the rest of "everything".
    importyaml.scaleway-secret = {
      # `importyaml`'s local-file branch expects an already-store-copied
      # path string (unlike its remote-URL branch, a bare repo-relative
      # path string isn't visible inside the sandboxed build that parses
      # it) -- `builtins.path` copies it into the store immediately.
      src = toString (builtins.path { path = ../../secrets/scaleway-secret.enc.yaml; });
      # A single flat Secret manifest has nothing that needs
      # named/numbered-list override support, and skipping the conversion
      # avoids any risk of it touching the sops metadata's own `age` list.
      convertLists = false;
    };
    kubernetes.resources.none.ClusterSecretStore.scaleway = {
      spec = {
        provider.scaleway = {
          region = "nl-ams";
          projectId = "cbc08bd9-d5af-4258-b8b7-21f5d5ae481a";
          accessKey.secretRef = {
            namespace = "kube-system";
            name = "scaleway";
            key = "SCW_ACCESS_KEY";
          };
          secretKey.secretRef = {
            namespace = "kube-system";
            name = "scaleway";
            key = "SCW_SECRET_KEY";
          };
        };
      };
    };
  };
}
