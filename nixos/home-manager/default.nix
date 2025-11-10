{
  config,
  pkgs,
  ...
}:
{
  imports = [
    ./fish.nix
    ./helix.nix
  ];
  config = {
    # Better cat
    programs.bat.enable = true;
    # Better find
    programs.fd.enable = true;
    # Better ls
    programs.lsd.enable = true;
    # Better grep
    programs.ripgrep.enable = true;
    # Install htop
    programs.htop.enable = true;
    # Packages added to PATH
    home.packages = with pkgs; [
      stern # Better kubectl logs
      kluctl # Pruning YAML apply tool
      kubectx
      clusterctl # ClusterAPI CLI tool
      waypipe # Wayland over SSH (clipboard sharing)
      wl-clipboard # Wayland CLI clipboard management
      cloud-init # For cleaning cloud-init semaphore
    ];
    # Set KUBECONFIG to where ClusterAPI installs it
    home.sessionVariables = {
      KUBECONFIG = "${config.home.homeDirectory}/.kube/config";
    };
  };
}
