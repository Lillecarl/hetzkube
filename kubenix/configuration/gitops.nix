{ config, lib, ... }:
let
  # Every Application CR is itself managed by "bootstrap" -- app-of-apps root
  # that self-manages, so a change to sync policy or adding a third
  # Application later just flows through the same `ekn commit` pipeline as
  # everything else.
  mkApplication =
    path:
    { ignoreDifferences ? [ ] }:
    {
      metadata.namespace = "argocd";
      ekn.gitOpsTarget = "bootstrap";
      spec = {
        project = "default";
        source = {
          repoURL = "https://github.com/Lillecarl/hetzkube.git";
          targetRevision = config.gitops.branch;
          inherit path;
        };
        destination = {
          server = "https://kubernetes.default.svc";
          namespace = "argocd";
        };
        # Automated as of the rollout plan's final step: the diff-
        # verification phase confirmed ArgoCD reconciling "everything" is a
        # no-op against the kluctl-managed cluster (module the known
        # tracking-id/benign-drift/Cilium-initContainer-reorder items), so
        # both Applications flip to automated together with kluctl.nix's
        # excludeGitopsTargets picking up "everything" in the same change --
        # otherwise there'd be a window where ArgoCD self-heals/prunes the
        # same objects kluctl also actively deploys (prune wars, drift
        # resets), which is exactly the risk kluctl.nix's own comments call
        # out.
        syncPolicy = {
          automated = {
            selfHeal = true;
            prune = true;
          };
          # Classic client-side `kubectl apply` stores the whole previous
          # object in the kubectl.kubernetes.io/last-applied-configuration
          # annotation, capped at 262144 bytes -- large CRDs (ArgoCD's own
          # applicationsets.argoproj.io, VictoriaMetrics', cert-manager's)
          # blow past that and fail to sync. Server-side apply doesn't use
          # that annotation at all, matching what `ekn kubeapply` already
          # does for direct applies.
          syncOptions = [ "ServerSideApply=true" ];
        };
        inherit ignoreDifferences;
      };
    };
in
{
  config = lib.mkIf (config.stage == "full") {
    gitops = {
      enable = true;
      branch = "deploy";
      targets = {
        bootstrap.branch = config.gitops.branch;
        bootstrap.path = "bootstrap";
        everything.branch = config.gitops.branch;
        everything.path = "everything";
      };
    };

    kubernetes.apiMappings = {
      Application = "argoproj.io/v1alpha1";
      AppProject = "argoproj.io/v1alpha1";
    };

    kubernetes.objects.argocd.Application = {
      bootstrap = mkApplication "bootstrap" { };
      everything = mkApplication "everything" {
        # These 3 Secrets' real content is generated/rotated by Cilium's own
        # agent at runtime (self-signed CA + leaf certs), never a Nix-authored
        # value -- kluctl already carries the matching kluctl.io/ignore-diff
        # annotation on them (kubenix/modules/cilium.nix) for the same reason.
        # ArgoCD has no equivalent respect for that annotation, so without
        # this, syncing "everything" would blow away Cilium's live-generated
        # cert material with whatever stale value is in kubernetes.generated.
        ignoreDifferences = map (name: {
          group = "";
          kind = "Secret";
          namespace = "kube-system";
          inherit name;
          jsonPointers = [ "/data" ];
        }) [ "cilium-ca" "hubble-server-certs" "hubble-relay-client-certs" ];
      };
    };

    # ArgoCD's own installed manifests (namespace, CRDs, controllers) are
    # managed by "bootstrap", not "everything" -- ArgoCD must exist before it
    # can sync anything else.
    importyaml.argocd.overrides = [
      # Upstream install.yaml omits metadata.namespace on namespaced objects
      # (it's meant to be applied via `kubectl apply -n argocd`); default it
      # for anything that isn't cluster-scoped.
      (
        object:
        if
          !(lib.elem object.kind [
            "CustomResourceDefinition"
            "ClusterRole"
            "ClusterRoleBinding"
            "Namespace"
          ])
          && !(object.metadata ? namespace)
        then
          lib.recursiveUpdate object { metadata.namespace = "argocd"; }
        else
          object
      )
      (object: object // { ekn.gitOpsTarget = "bootstrap"; })
    ];

    # Any generated object that isn't already explicitly routed to a GitOps
    # target (via ekn.gitOpsTarget set elsewhere) flows to the single
    # "everything" Application by default. This is what lets every existing
    # module keep working unmodified instead of hand-annotating each one.
    kubernetes.transformers = [
      (
        object:
        if (object.ekn.gitOpsTarget or null) == null then
          lib.recursiveUpdate object { ekn.gitOpsTarget = "everything"; }
        else
          object
      )
    ];
  };
}
