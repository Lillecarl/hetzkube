{
  config,
  pkgs,
  lib,
  ...
}:
let
  moduleName = "argocd";
  cfg = config.${moduleName};
in
{
  options.${moduleName} = {
    enable = lib.mkEnableOption moduleName;
    version = lib.mkOption {
      type = lib.types.nonEmptyStr;
    };
    ksops = {
      enable = lib.mkEnableOption "ksops support in argocd-repo-server (Kustomize + SOPS decryption at sync time)";
      secretName = lib.mkOption {
        type = lib.types.nonEmptyStr;
        default = "sops-age-key";
        description = ''
          Name of the Secret (in the argocd namespace) holding the
          SOPS_AGE_KEY_FILE identity, mounted read-only into
          argocd-repo-server. ekn never handles key material -- this
          Secret is created out-of-band by scripts/bootstrap-argocd.py via
          a direct kubectl apply, never through Nix/git.
        '';
      };
    };
  };
  config = lib.mkMerge [
    (lib.mkIf cfg.enable {
      # Upstream install.yaml deliberately omits this (their docs expect
      # `kubectl create namespace argocd` first) -- declare it so the
      # namespace is part of kubernetes.generated like everything else,
      # instead of only existing because bootstrap-argocd.py creates it by
      # hand before applying anything else. Routed to "bootstrap" like the
      # rest of ArgoCD's own install objects (see gitops.nix's
      # importyaml.argocd.overrides) -- it needs to exist before ArgoCD can
      # run, so it belongs in the same one-time bootstrap apply, not synced
      # in later via "everything".
      kubernetes.resources.none.Namespace.argocd.ekn.gitOpsTarget = "bootstrap";
      importyaml.argocd.src = "https://raw.githubusercontent.com/argoproj/argo-cd/v${cfg.version}/manifests/install.yaml";
    })
    (lib.mkIf cfg.ksops.enable {
      # Wires argocd-repo-server up to build Kustomize trees through the
      # ksops KRM-generator plugin, so ArgoCD can decrypt SOPS-encrypted
      # Secrets that `ekn commit` writes as ksops generators (see
      # easykubenix's git.py flatten_manifests(kustomize=True)).
      importyaml.argocd.overrides = [
        (
          object:
          if object.kind == "ConfigMap" && object.metadata.name == "argocd-cm" then
            lib.recursiveUpdate object {
              data."kustomize.buildOptions" = "--enable-alpha-plugins --enable-exec";
            }
          else
            object
        )
        # `importyaml`'s convertLists (see easykubenix's
        # lib/default.nix:kubeListsToAttrs) has already turned every
        # name-keyed list on this object (volumes, containers, env,
        # volumeMounts) into a `_namedlist` attrset keyed by `name` by the
        # time overrides run -- `initContainers` is the one exception,
        # kept as an order-preserving `_numberedlist` (numeric-string
        # keys) since init container order matters. So this patches by
        # merging into those attrsets (new key = new list element) rather
        # than list-appending. One consequence: unlike
        # viaduct-ai/kustomize-sops's own docs, which mount the same
        # "custom-tools" volume twice via two different subPaths, we
        # mount it once (two volumeMounts with the same `name` would
        # collide as the same attrset key and silently drop one) and add
        # its directory to PATH instead of shadowing
        # /usr/local/bin/{kustomize,ksops} individually.
        (
          object:
          if object.kind == "Deployment" && object.metadata.name == "argocd-repo-server" then
            let
              podSpec = object.spec.template.spec;
              nextInitContainerIndex = toString (
                lib.length (lib.attrNames (lib.removeAttrs podSpec.initContainers [ "_numberedlist" ]))
              );
              repoServerEnv = podSpec.containers.argocd-repo-server.env;
              repoServerMounts = podSpec.containers.argocd-repo-server.volumeMounts;
            in
            lib.recursiveUpdate object {
              spec.template.spec = {
                initContainers = podSpec.initContainers // {
                  ${nextInitContainerIndex} = {
                    name = "install-ksops";
                    image = "viaductoss/ksops:v4.5.1";
                    command = [
                      "/usr/local/bin/ksops"
                      "install"
                      "--with-kustomize"
                      "/custom-tools"
                    ];
                    volumeMounts = lib.mkNamedList {
                      custom-tools.mountPath = "/custom-tools";
                    };
                  };
                };
                volumes = podSpec.volumes // {
                  custom-tools.emptyDir = { };
                  sops-age.secret.secretName = cfg.ksops.secretName;
                };
                containers = podSpec.containers // {
                  argocd-repo-server = podSpec.containers.argocd-repo-server // {
                    env = repoServerEnv // {
                      SOPS_AGE_KEY_FILE.value = "/sops-age/key.txt";
                      # quay.io/argoproj/argocd is Debian-based; this is
                      # its default PATH with /custom-tools prepended so
                      # the ksops-installed kustomize/ksops binaries are
                      # found without shadowing the image's own
                      # /usr/local/bin/argocd-repo-server.
                      PATH.value = "/custom-tools:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin";
                    };
                    volumeMounts = repoServerMounts // {
                      custom-tools.mountPath = "/custom-tools";
                      sops-age = {
                        mountPath = "/sops-age";
                        readOnly = true;
                      };
                    };
                  };
                };
              };
            }
          else
            object
        )
      ];
    })
  ];
}
