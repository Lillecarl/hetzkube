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
      ref = "918e292b1a9151aea52a748f00d91d78f744e9d8";
    };
  };
  plugins = [
    (registry.keycloak.keycloak.latestWhere (v: pkgs.lib.versionOlder v "6.0.0"))
    (registry.hashicorp.kubernetes.latestWhere (v: pkgs.lib.versionOlder v "4.0.0"))
    (registry.scaleway.scaleway.latestWhere (v: pkgs.lib.versionOlder v "3.0.0"))
  ];
  tofu = pkgs.opentofu.withPlugins (_: plugins);

  module =
    let
      terranix-config = pkgs.writeText "terranix-config" (builtins.toJSON terranix.config);
    in
    pkgs.runCommand "tofu-initialized"
      {
        buildInputs = [
          tofu
          pkgs.jq
        ];
      } # bash
      ''
        mkdir $out
        cd $out
        jq < ${terranix-config} >> config.tf.json
        tofu init -backend=false
      '';

  run = pkgs.writeShellApplication {
    name = "terranix";
    runtimeInputs = [
      pkgs.opentofu
      pkgs.rsync
    ];
    text = ''
      set -x
      rsync --archive --chmod=u+w ${module}/ .
      exec tofu "$@"
    '';
  };
}
