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
    networking.nameservers = lib.mkForce [ ];
    # Enable systemd-networkd
    systemd.network.enable = true;
  };
}
