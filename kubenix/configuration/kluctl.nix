{
  x86Pkgs,
  config,
  lib,
  ...
}:
{
  copyDerivations = [
    x86Pkgs.nix-csi-builder-env
  ];
  kluctl = {
    # Add SOPS secrets
    deployment.vars = [ { file = "secrets/all.yaml"; } ];
    files."secrets/all.yaml" = builtins.readFile ../../secrets/all.yaml;
    # Disable templating for default resource project
    files."default/.templateignore" = "*";
    # Put priorities on resources, this also excludes the from the templateignore above
    resourcePriority = {
      Namespace = 10;
      CustomResourceDefinition = 10;
      Secret = 20;
    };
    preDeployScript = # bash
      ''
        nix copy \
          --substitute-on-destination \
          --no-check-sigs \
          --from local?read-only=true \
          --to ssh-ng://nix@nixcache.lillecarl.com?port=2222 \
          ${lib.join " " config.copyDerivations} \
          -v || true
      '';

  };
}
