{
  config,
  pkgs,
  lib,
  ...
}:
{
  config = {
    lib.anywhereScript =
      pkgs.writeScriptBin "imageinstall" # bash
        ''
          #! ${pkgs.runtimeShell}
          set -x
          PATH=${lib.makeBinPath [ pkgs.nixos-anywhere ]}:$PATH
          nixos-anywhere \
            --flake .#${config.lib.hetzkube.configName} \
            --target-host root@${config.lib.hetzkube.ip} \
            --build-on remote \
            --kexec https://github.com/nix-community/nixos-images/releases/download/nixos-25.05/nixos-kexec-installer-noninteractive-${pkgs.stdenv.hostPlatform.system}.tar.gz
          ssh-keygen -R ${config.lib.hetzkube.ip}
        '';
    lib.rebuildScript =
      pkgs.writeScriptBin "imagedeploy" # bash
        ''
          #! ${pkgs.runtimeShell}
          PATH=${lib.makeBinPath [ pkgs.nixos-rebuild-ng ]}:$PATH
          set -x
          nixos-rebuild switch \
            --use-substitutes \
            --file . \
            --attr nixosConfigurations.${config.lib.hetzkube.configName} \
            --target-host root@${config.lib.hetzkube.ip}

            # --build-host root@${config.lib.hetzkube.ip}
        '';
  };
}
