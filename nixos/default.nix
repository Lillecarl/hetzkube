{
  config,
  lib,
  inputs,
  pkgs,
  modulesPath,
  ...
}:
{
  imports = [
    inputs.disko.nixosModules.disko
    inputs.srvos.nixosModules.server
    inputs.home-manager.nixosModules.home-manager
    (modulesPath + "/profiles/qemu-guest.nix")
    ./cloud-init.nix
    ./disko.nix
    ./installscript.nix
    ./kubernetes.nix
    ./networking.nix
    ./nix.nix
  ];

  config = {
    # Don't change this unless you know what you're doing. It probably doesn't
    # matter since we don't run much from NixOS at all but it's in their docs
    # to no touchy touchy so beware of what you're doing.
    system.stateVersion = "25.05";

    boot.loader.grub = {
      enable = true;
      device = "/dev/sda"; # BIOS boot
      efiSupport = true; # UEFI boot
      efiInstallAsRemovable = true; # So we don't need to set efivars
    };
    # Automatically grow rootfs
    fileSystems."/".autoResize = true;

    boot.initrd.availableKernelModules = [
      "ahci"
      "sd_mod"
      "sr_mod"
      "virtio_pci"
      "virtio_scsi"
      "xhci_pci"
    ];

    # Get impure hostname
    networking.hostName =
      let
        hostNameFile = /etc/hetzinfo/hostName;
      in
      if builtins.pathExists hostNameFile then builtins.readFile hostNameFile else "image";

    # Get impure swapfile size
    swapDevices =
      let
        memoryFile = /etc/hetzinfo/memoryMB;
      in
      lib.optional (lib.pathExists memoryFile) {
        device = "/swapfile";
        size = lib.toInt (builtins.readFile memoryFile);
      };

    # Latest stable Kernel is nice when running containers
    boot.kernelPackages = pkgs.linuxPackages_latest;
    # Set timezone
    time.timeZone = "Europe/Stockholm";
    # Enable a good shell
    programs.fish.enable = true;
    # Git required to fetch up2date node config
    programs.git.enable = true;

    # Carl uses Kitty terminal and disk space is cheap!
    environment.enableAllTerminfo = true;

    services.openssh = {
      enable = true;
      openFirewall = true;
    };

    users = {
      mutableUsers = false;
      users.root = {
        # Don't hack this pls
        hashedPassword = "$y$j9T$OrH.jbsHxfI2KFYJhaIyk/$sqU6GT8uslzboO0VTRi/ARPd8MJIdSPFKq7WZjSMVK3";
        openssh.authorizedKeys.keyFiles = [
          ../pubkeys/carl.pub
        ];
      };
      users.hetzkube = {
        isNormalUser = true;
        extraGroups = [ "wheel" ];
        openssh.authorizedKeys.keyFiles = [
          ../pubkeys/carl.pub
        ];
        shell = pkgs.fish;
      };
    };
    home-manager.backupFileExtension = "bak";
    home-manager.users.hetzkube = {
      imports = [ ./home-manager ];
      home.stateVersion = config.system.stateVersion;
    };
  };
}
