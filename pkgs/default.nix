self: pkgs: {
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
}
