{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    flake-compatish.url = "github:lillecarl/flake-compatish";
    home-manager = {
      url = "github:nix-community/home-manager/release-25.05";
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
    nix2conatiner = {
      url = "github:nlewo/nix2container";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    terranix = {
      url = "github:terranix/terranix";
      flake = false; # I don't wanna pull in their dependencies.
    };
  };
  outputs = inputs: {
    nixosConfigurations.image-aarch64-linux = inputs.nixpkgs.lib.nixosSystem {
      system = "aarch64-linux";
      modules = [
        ./nixos
        {
          lib.hetzkube = {
            ip = "37.27.47.29";
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
            ip = "37.27.91.156";
            configName = "image-x86_64-linux";
          };
        }
      ];
      specialArgs = { inherit inputs; };
    };
  };
}
