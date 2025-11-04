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
    terranix = {
      url = "github:terranix/terranix";
      flake = false; # I don't wanna pull in their dependencies.
    };
  };
  outputs = inputs: {
    nixosConfigurations.image-arm = inputs.nixpkgs.lib.nixosSystem {
      system = "aarch64-linux";
      modules = [
        ./nixos
        {
          lib.hetzkube = {
            ip = "37.27.47.29";
            configName = "image-arm";
          };
        }
      ];
      specialArgs = { inherit inputs; };
    };
    nixosConfigurations.image-x86 = inputs.nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        ./nixos
        {
          lib.hetzkube = {
            ip = "37.27.91.156";
            configName = "image-x86";
          };
        }
      ];
      specialArgs = { inherit inputs; };
    };
  };
}
