{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    home-manager = {
      url = "github:nix-community/home-manager/release-25.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    srvos = {
      url = "github:nix-community/srvos";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    flake-compatish = {
      url = "github:lillecarl/flake-compatish";
      flake = false;
    };
    terranix = {
      url = "github:terranix/terranix";
      flake = false; # I don't wanna pull in their dependencies.
    };
    easykubenix = {
      url = "github:lillecarl/easykubenix";
      flake = false;
    };
    nix-csi = {
      url = "github:lillecarl/nix-csi";
      flake = false;
    };
  };
  outputs = inputs: {
    nixosConfigurations.image-aarch64-linux = inputs.nixpkgs.lib.nixosSystem {
      system = "aarch64-linux";
      modules = [
        ./nixos
        {
          lib.hetzkube = {
            ip = "37.27.248.233";
            configName = "image-aarch64-linux";
          };
        }
      ];
      specialArgs = { inherit inputs; };
    };
    nixosConfigurations.image-x86_64-linux = inputs.nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        ./nixos
        {
          lib.hetzkube = {
            ip = "46.62.244.185";
            configName = "image-x86_64-linux";
          };
        }
      ];
      specialArgs = { inherit inputs; };
    };
  };
}
