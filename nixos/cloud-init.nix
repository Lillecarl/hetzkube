{
  pkgs,
  lib,
  ...
}:
{
  config = {
    services.cloud-init = {
      enable = true;
      btrfs.enable = false;
      network.enable = true;
      settings = {
        # WE MANAGE NETWORKING THANKS CLOUD-INIT
        # network.config = "disabled";
        # disable_fallback_netcfg = true;
        # Don't run any modules we don't need
        cloud_config_modules = lib.mkForce [
          "runcmd"
          # "disable-ec2-metadata"
          # "disk_setup"
          # "mounts"
          # "set-passwords"
          "ssh"
          "ssh-import-id"
          # "timezone"
        ];
        cloud_final_modules = lib.mkForce [
          "scripts-per-boot"
          "scripts-per-instance"
          "scripts-per-once"
          "scripts-user"
          "scripts-vendor"
          # "final-message"
          # "keys-to-console"
          # "phone-home"
          # "power-state-change"
          # "rightscale_userdata"
          # "ssh-authkey-fingerprints"
        ];
        cloud_init_modules = lib.mkForce [
          "write-files"
          # "bootcmd"
          # "ca-certs"
          # "growpart"
          # "migrator"
          # "resizefs"
          # "resolv_conf"
          # "rsyslog"
          "seed_random"
          "update_hostname"
          # "users-groups"
        ];
      };
      extraPackages = with pkgs; [
        btrfs-progs
        lvm2
        nixos-rebuild-ng
        kubernetes
        cloud-init
      ];
    };
    # Don't restart cloud-init if it changes when rebuilding since this can
    # break if you're running rebuilds in cloud-init.
    systemd.services.cloud-config.restartIfChanged = false;
    systemd.services.cloud-final.restartIfChanged = false;
    systemd.services.cloud-init-local.restartIfChanged = false;
    systemd.services.cloud-init.restartIfChanged = false;
  };
}
