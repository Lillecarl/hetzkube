rec {
  root = import ../. { };
  inherit (root) pkgs;
  inherit (pkgs) lib;

  terranix = import "${root.flake.inputs.terranix}/core" {
    inherit pkgs;
    modules = [
      ./terranix.nix
      {
        # Configure required_providers with our tofu providers
        config = lib.pipe plugins [
          (map (plugin: {
            name = plugin.passthru.name;
            value = plugin.passthru.config;
          }))
          lib.listToAttrs
          (x: {
            terraform.required_providers = x;
          })
        ];
      }
    ];
  };

  registry = import ./registry.nix {
    inherit pkgs;
    registry = builtins.fetchTree {
      type = "github";
      owner = "opentofu";
      repo = "registry";
      ref = "main";
    };
  };
  plugins = [
    (registry.keycloak.keycloak.latestWhere (v: pkgs.lib.versionOlder v "6.0.0"))
    (registry.hashicorp.kubernetes.latestWhere (v: pkgs.lib.versionOlder v "4.0.0"))
    (registry.scaleway.scaleway.latestWhere (v: pkgs.lib.versionOlder v "3.0.0"))
    (registry.hashicorp.random.latestWhere (v: pkgs.lib.versionOlder v "4.0.0"))
  ];
  tofuUnwrapped = pkgs.opentofu.withPlugins (_: plugins);

  # config.tf.json plus a matching .terraform.lock.hcl, baked in by a real
  # `tofu init -backend=false` at build time (offline: every provider is
  # already local via withPlugins, and the real "kubernetes" backend needs a
  # live cluster anyway, so backend init genuinely happens later, at
  # runtime). Nothing else lives here -- the writable `.terraform`
  # provider-install/backend-pointer directory is kept outside the store
  # (see `run` below, via $TF_DATA_DIR), so this path stays read-only.
  module =
    let
      terranix-config = pkgs.writeText "terranix-config" (builtins.toJSON terranix.config);
    in
    pkgs.runCommand "tofu-initialized"
      {
        nativeBuildInputs = [
          tofuUnwrapped
          pkgs.jq
        ];
      }
      ''
        mkdir "$out"
        jq < ${terranix-config} > "$out/config.tf.json"
        cd "$out"
        TF_DATA_DIR=$TMPDIR/.terraform tofu init -backend=false -input=false
      '';

  # Wraps the plugin-bundled tofu so it always operates on `module` (in the
  # store, read-only) via -chdir, while its own writable state --
  # provider-install dir and the kubernetes backend's local pointer file --
  # lives in $TF_DATA_DIR, outside the store. Defaults to tf/.terraform
  # (this directory, baked in at build time) rather than $PWD/.terraform --
  # -chdir changes directory before anything else runs, so a $PWD-relative
  # default would land wherever the caller happened to invoke this from
  # (e.g. the repo root), outside this directory's own .gitignore coverage.
  run = pkgs.writeShellApplication {
    name = "terranix";
    runtimeInputs = [ tofuUnwrapped ];
    text = ''
      export TF_DATA_DIR="''${TF_DATA_DIR:-${toString ./.}/.terraform}"
      mkdir -p "$TF_DATA_DIR"
      exec tofu -chdir=${module} "$@"
    '';
  };
}
