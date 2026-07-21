{ config, lib, ... }:
let
  bootstrapApp = config.kubernetes.objects.argocd.Application.bootstrap;
  everythingApp = config.kubernetes.objects.argocd.Application.everything;

  # Every Application CR is itself managed by "bootstrap" -- app-of-apps root
  # that self-manages, so a change to sync policy or adding a third
  # Application later just flows through the same `ekn commit` pipeline as
  # everything else.
  mkApplication = path: {
    metadata.namespace = "argocd";
    ekn.argo = [ bootstrapApp ];
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
      # Manual sync until the rollout plan's diff-verification step (Phase 4)
      # confirms ArgoCD reconciling is a no-op against the kluctl-managed
      # cluster. Flip to automated (selfHeal+prune) afterwards.
      syncPolicy = { };
    };
  };
in
{
  config = lib.mkIf (config.stage == "full") {
    gitops = {
      enable = true;
      branch = "deploy";
    };

    kubernetes.apiMappings = {
      Application = "argoproj.io/v1alpha1";
      AppProject = "argoproj.io/v1alpha1";
    };

    kubernetes.objects.argocd.Application = {
      bootstrap = mkApplication "bootstrap";
      everything = mkApplication "everything";
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
      (object: object // { ekn.argo = [ bootstrapApp ]; })
    ];

    # Any generated object that isn't already explicitly routed to a GitOps
    # target (via ekn.argo/ekn.flux set elsewhere) flows to the single
    # "everything" Application by default. This is what lets every existing
    # module keep working unmodified instead of hand-annotating each one.
    kubernetes.transformers = [
      (
        object:
        if (object.ekn.argo or [ ]) == [ ] && (object.ekn.flux or [ ]) == [ ] then
          lib.recursiveUpdate object { ekn.argo = [ everythingApp ]; }
        else
          object
      )
    ];
  };
}
