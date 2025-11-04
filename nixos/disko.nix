{ ... }:
{
  disko.devices = {
    disk = {
      local = {
        type = "disk";
        device = "/dev/sda";
        content = {
          type = "gpt";
          partitions = {
            # BIOS boot partition for GRUB on GPT
            boot = {
              priority = 0;
              size = "1M";
              type = "EF02"; # This is the type for a BIOS boot partition
            };
            ESP = {
              priority = 1;
              size = "1G";
              type = "EF00";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
                mountOptions = [ "umask=0077" ];
              };
            };
            primary = {
              priority = 2;
              size = "100%";
              content = {
                type = "btrfs";
                extraArgs = [ "-f" ];
                subvolumes =
                  let
                    mountOptions = [
                      "defaults"
                      "compress=zstd"
                      "lazytime"
                      "ssd"
                      "autodefrag"
                    ];
                  in
                  {
                    "@root" = {
                      mountpoint = "/";
                      inherit mountOptions;
                    };
                    "@nix" = {
                      mountpoint = "/nix";
                      inherit mountOptions;
                    };
                  };
              };
            };
          };
        };
      };
    };
  };
}
