final: prev:
let
  inherit (prev) lib;
in
{
  hetzInfo =
    prev.writeScriptBin "hetzInfo" # bash
      ''
        #! ${prev.runtimeShell}
        mkdir --parents /etc/hetzinfo
        # Get memory in MB (for swap setup)
        awk '/MemTotal/ {printf "%.0f", $2/1024}' /proc/meminfo > /etc/hetzinfo/memoryMB
        # Fetch hostname
        curl http://169.254.169.254/hetzner/v1/metadata/hostname -o /etc/hetzinfo/hostName
      '';

  python-jsonpath = prev.python3Packages.callPackage ./python-jsonpath.nix { };
  kr8s = prev.python3Packages.callPackage ./kr8s.nix { inherit (final) python-jsonpath; };
  cheapam = prev.python3Packages.callPackage ../cheapam { };
  pgadmin-launcher =
    prev.writeScriptBin "pgadmin-launcher" # bash
      ''
        #! ${prev.runtimeShell}
        set -euo pipefail
        export PATH=${
          lib.makeBinPath [
            prev.coreutils-full
          ]
        }:$PATH
        mkdir --parents /var/lib/pgadmin
        mkdir --parents /var/log/pgadmin
        (
          echo $INITIAL_EMAIL
          echo $INITIAL_PASSWORD
          echo $INITIAL_PASSWORD
        ) | ${lib.getExe' prev.pgadmin4 "pgadmin4-cli"} setup-db
        exec ${lib.getExe prev.pgadmin4} "$@"
      '';
}
