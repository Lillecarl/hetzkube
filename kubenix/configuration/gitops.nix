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
        ignoreDifferences =
          map (name: {
            group = "";
            kind = "Secret";
            namespace = "kube-system";
            inherit name;
            jsonPointers = [ "/data" ];
          }) [ "cilium-ca" "hubble-server-certs" "hubble-relay-client-certs" ]
          # The rest of these are all the same shape of problem: a
          # CRD's own admission webhook/controller fills in structural
          # defaults (or writes back real runtime state) for fields our
          # declared manifest leaves unset/terser, so the object is
          # permanently "OutOfSync" even though there's no meaningful
          # drift -- confirmed via `ekn clusterdiff` showing zero
          # difference from ekn's own server-side-apply-dry-run
          # perspective, only ArgoCD's own field-manager-tracked
          # comparison disagreeing. Every path here was taken from a
          # live object's actual defaulted value (`kubectl get -o
          # yaml`), not guessed -- narrowly scoped to exactly the
          # default-filled/controller-owned fields, never a whole
          # `/spec`, so a real future Nix-driven change to any *other*
          # field on these kinds still syncs normally.
          ++ [
            # ExternalSecret (external-secrets.io): the ESO webhook fills in
            # per-item defaults on create.
            {
              group = "external-secrets.io";
              kind = "ExternalSecret";
              jqPathExpressions = [
                ".spec.data[]?.remoteRef.conversionStrategy"
                ".spec.data[]?.remoteRef.decodingStrategy"
                ".spec.data[]?.remoteRef.metadataPolicy"
                ".spec.data[]?.remoteRef.nullBytePolicy"
              ];
              jsonPointers = [
                "/spec/target/creationPolicy"
                "/spec/target/deletionPolicy"
                "/spec/target/template/engineVersion"
                "/spec/target/template/mergePolicy"
              ];
            }
            # Gateway API (gateway.networking.k8s.io): the CRD schema
            # defaults group/kind/weight on object references when omitted.
            {
              group = "gateway.networking.k8s.io";
              kind = "Gateway";
              jqPathExpressions = [ ".spec.listeners[]?.tls?.certificateRefs[]?.group" ];
            }
            {
              group = "gateway.networking.k8s.io";
              kind = "HTTPRoute";
              jqPathExpressions = [
                ".spec.parentRefs[]?.group"
                ".spec.parentRefs[]?.kind"
                ".spec.rules[]?.backendRefs[]?.group"
                ".spec.rules[]?.backendRefs[]?.kind"
                ".spec.rules[]?.backendRefs[]?.weight"
              ];
            }
            # grafana-operator's Grafana CR embeds an HTTPRoute-shaped spec
            # subject to the same Gateway API defaulting, and separately
            # writes the resolved/running Grafana version back into spec.
            {
              group = "grafana.integreatly.org";
              kind = "Grafana";
              jqPathExpressions = [
                ".spec.httpRoute.spec.parentRefs[]?.group"
                ".spec.httpRoute.spec.parentRefs[]?.kind"
                ".spec.httpRoute.spec.rules[]?.backendRefs[]?.group"
                ".spec.httpRoute.spec.rules[]?.backendRefs[]?.kind"
                ".spec.httpRoute.spec.rules[]?.backendRefs[]?.weight"
              ];
              jsonPointers = [ "/spec/version" ];
            }
            # Kyverno ClusterPolicy: the policy admission webhook fills in
            # rule-engine defaults left unset in our declared policies.
            {
              group = "kyverno.io";
              kind = "ClusterPolicy";
              jqPathExpressions = [ ".spec.rules[]?.skipBackgroundRequests" ];
              jsonPointers = [
                "/spec/admission"
                "/spec/background"
                "/spec/emitWarning"
                "/spec/validationFailureAction"
              ];
            }
            # CloudNativePG Cluster (postgresql.cnpg.io): CNPG's webhook is
            # extremely defaulty -- these are exactly the fields it fills in
            # beyond what we declare (instances/storage/managed.roles/
            # enablePDB/enableSuperuserAccess), left out on purpose so a real
            # change to any of *those* still syncs.
            {
              group = "postgresql.cnpg.io";
              kind = "Cluster";
              jqPathExpressions = [
                ".spec.managed.roles[]?.connectionLimit"
                ".spec.managed.roles[]?.ensure"
                ".spec.managed.roles[]?.inherit"
              ];
              jsonPointers = [
                "/spec/affinity"
                "/spec/bootstrap"
                "/spec/failoverDelay"
                "/spec/imageName"
                "/spec/logLevel"
                "/spec/maxSyncReplicas"
                "/spec/minSyncReplicas"
                "/spec/monitoring"
                "/spec/postgresGID"
                "/spec/postgresUID"
                "/spec/postgresql"
                "/spec/primaryUpdateMethod"
                "/spec/primaryUpdateStrategy"
                "/spec/probes"
                "/spec/replicationSlots"
                "/spec/resources"
                "/spec/smartShutdownTimeout"
                "/spec/startDelay"
                "/spec/stopDelay"
                "/spec/switchoverDelay"
                "/spec/storage/resizeInUseVolumes"
              ];
            }
            # ClusterAPI/CAPH (cluster.x-k8s.io, controlplane.cluster.x-k8s.io,
            # infrastructure.cluster.x-k8s.io): same structural-default story,
            # PLUS two genuinely controller/human-owned fields that must never
            # be statically declared: Cluster.spec.controlPlaneEndpoint (set
            # by CAPI once the control plane is up) and
            # KubeadmControlPlane.spec.rolloutAfter (the field the documented
            # "Re-roll the Control-Plane" procedure patches by hand to
            # trigger a rollout -- if this were declared in Nix instead of
            # ignored, the next automated selfHeal sync would revert a manual
            # re-roll trigger right back to the stale Nix value).
            {
              group = "cluster.x-k8s.io";
              kind = "Cluster";
              jsonPointers = [
                "/spec/controlPlaneEndpoint"
                "/spec/controlPlaneRef/namespace"
                "/spec/infrastructureRef/namespace"
              ];
            }
            {
              group = "cluster.x-k8s.io";
              kind = "MachineDeployment";
              jsonPointers = [
                "/spec/minReadySeconds"
                "/spec/progressDeadlineSeconds"
                "/spec/revisionHistoryLimit"
                "/spec/selector"
                "/spec/strategy"
                "/spec/template/metadata/labels"
                "/spec/template/spec/infrastructureRef/namespace"
                "/spec/template/spec/bootstrap/configRef/namespace"
              ];
            }
            {
              group = "cluster.x-k8s.io";
              kind = "MachineHealthCheck";
              jqPathExpressions = [ ".spec.unhealthyConditions[]?.timeout" ];
              jsonPointers = [
                "/spec/nodeStartupTimeout"
                "/spec/remediationTemplate/namespace"
              ];
            }
            {
              group = "controlplane.cluster.x-k8s.io";
              kind = "KubeadmControlPlane";
              jsonPointers = [
                "/spec/kubeadmConfigSpec/clusterConfiguration/dns"
                "/spec/kubeadmConfigSpec/clusterConfiguration/networking"
                "/spec/kubeadmConfigSpec/format"
                "/spec/kubeadmConfigSpec/initConfiguration/localAPIEndpoint"
                "/spec/kubeadmConfigSpec/initConfiguration/nodeRegistration/imagePullPolicy"
                "/spec/kubeadmConfigSpec/joinConfiguration/discovery"
                "/spec/kubeadmConfigSpec/joinConfiguration/nodeRegistration/imagePullPolicy"
                "/spec/machineTemplate/infrastructureRef/namespace"
                "/spec/machineTemplate/metadata"
                "/spec/rolloutAfter"
                "/spec/rolloutStrategy"
              ];
            }
            {
              group = "infrastructure.cluster.x-k8s.io";
              kind = "HCloudRemediationTemplate";
              jsonPointers = [ "/spec/template/spec/strategy/timeout" ];
            }
            # A manual `kubectl rollout restart` (as opposed to one driven by
            # a real template change) stamps this annotation, which then
            # perpetually shows as live-only drift since it's owned by
            # kubectl's own field manager, not argocd-controller's.
            {
              group = "apps";
              kind = "Deployment";
              jsonPointers = [ "/spec/template/metadata/annotations/kubectl.kubernetes.io~1restartedAt" ];
            }
            {
              group = "apps";
              kind = "StatefulSet";
              jsonPointers = [ "/spec/template/metadata/annotations/kubectl.kubernetes.io~1restartedAt" ];
            }
          ];
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
