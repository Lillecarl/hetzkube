self: pkgs:
let
  inherit (pkgs) lib;
in
{
  hetzInfo =
    pkgs.writeScriptBin "hetzInfo" # bash
      ''
        #! ${pkgs.runtimeShell}
        mkdir --parents /etc/hetzinfo
        # Get memory in MB (for swap setup)
        awk '/MemTotal/ {printf "%.0f", $2/1024}' /proc/meminfo > /etc/hetzinfo/memoryMB
        # Fetch hostname
        curl http://169.254.169.254/hetzner/v1/metadata/hostname -o /etc/hetzinfo/hostName
      '';

  python-jsonpath = pkgs.python3Packages.callPackage ./python-jsonpath.nix { };
  kr8s = pkgs.python3Packages.callPackage ./kr8s.nix { inherit (self) python-jsonpath; };
  cheapam = pkgs.python3Packages.callPackage ../cheapam { };
  pgadmin-launcher =
    pkgs.writeScriptBin "pgadmin-launcher" # bash
      ''
        #! ${pkgs.runtimeShell}
        set -euo pipefail
        export PATH=${
          lib.makeBinPath [
            pkgs.coreutils-full
          ]
        }:$PATH
        mkdir --parents /var/lib/pgadmin
        mkdir --parents /var/log/pgadmin
        (
          echo $INITIAL_EMAIL
          echo $INITIAL_PASSWORD
          echo $INITIAL_PASSWORD
        ) | ${lib.getExe' pkgs.pgadmin4 "pgadmin4-cli"} setup-db
        exec ${lib.getExe pkgs.pgadmin4} "$@"
      '';
}
