{ config, lib, ... }:
{
  config = {
    # Use old interface naming scheme
    boot.kernelParams = [ "net.ifnames=0" ];
    # Disable cloud-init networking
    services.cloud-init.network.enable = true;
    # Use Ciliums hostfirewall feature
    networking.firewall.enable = lib.mkForce false;
    # Disable DHCP globally as it interferes with CNI operations
    networking.useDHCP = false;
    # Use Cloudflare nameservers, they're quite stable
    networking.nameservers = [
      "1.1.1.1"
      "2606:4700:4700::1111"
    ];
    environment.etc."resolv.conf".text = # resolv
      ''
        options edns0 trust-ad
        search .
        nameserver 1.1.1.1
        nameserver 2606:4700:4700::1111
      '';
    # Enable systemd-networkd
    systemd.network.enable = true;
    # Disable resolved
    services.resolved.enable = false;
  };
}
