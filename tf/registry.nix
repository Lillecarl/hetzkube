{
  pkgs ? import <nixpkgs> { },
  registry ? ./.,
}:
let
  inherit (pkgs) lib;

  mkTerraformProvider = lib.makeOverridable (
    {
      owner,
      repo,
      version,
      url,
      sha256,
      registry ? "registry.opentofu.org",
    }:
    let
      inherit (pkgs.go) GOARCH GOOS;
      # The canonical path where the provider binary will be installed.
      installPath = "$out/libexec/terraform-providers/${registry}/${owner}/${repo}/${version}/${GOOS}_${GOARCH}";
    in
    pkgs.stdenv.mkDerivation {
      pname = "tfprovider-${owner}-${repo}";
      inherit version;

      src = pkgs.fetchurl {
        inherit url sha256;
      };

      buildPhase = ":";
      dontUnpack = true;
      nativeBuildInputs = [ pkgs.unzip ];

      installPhase = ''
        # 1. Create the canonical directory and install the provider.
        mkdir -p "${installPath}"
        unzip -o $src -d "${installPath}"
        chmod +x "${installPath}"/terraform-provider-*
      '';
      passthru = {
        name = repo;
        config = {
          source = "${registry}/${owner}/${repo}";
          version = version;
        };
      };
    }
  );

  importJSON =
    {
      owner,
      repo,
      file,
    }:
    let
      data = builtins.fromJSON (builtins.readFile file);
      versions = lib.flatten (
        map (
          versionInfo:
          let
            target = lib.findFirst (
              t: t.os == pkgs.stdenv.hostPlatform.go.GOOS && t.arch == pkgs.stdenv.hostPlatform.go.GOARCH
            ) null versionInfo.targets;
          in
          lib.optional (target != null) {
            name = versionInfo.version;
            value = mkTerraformProvider {
              inherit owner repo;
              version = versionInfo.version;
              url = target.download_url;
              sha256 = target.shasum;
            };
          }
        ) data.versions
      );
      getLatest =
        name: versions:
        lib.pipe versions [
          (lib.sort (a: b: lib.versionAtLeast a.value.version b.value.version))
          lib.head
          (
            version:
            version
            // {
              inherit name;
            }
          )
          lib.toList
        ];

      latest = getLatest "latest" versions;
    in
    lib.listToAttrs (versions ++ latest);

  files = lib.filesystem.listFilesRecursive (registry + /providers);
in
lib.foldl' (
  acc: file:
  let
    registryPath = lib.pipe file [
      # filePath -> string
      toString
      # drop string context so we can use path parts as attrset names
      builtins.unsafeDiscardStringContext
      # split by path
      (lib.splitString "/")
      # take last two
      (lib.takeEnd 2)
    ];

    owner = lib.head registryPath;
    repo = lib.removeSuffix ".json" (lib.last registryPath);
  in
  lib.recursiveUpdate acc {
    ${owner} =
      let
        versions = importJSON {
          inherit owner repo file;
        };
      in
      {
        ${repo} = versions // {
          selectVersions = predicate: lib.filterAttrs (version: _: predicate version) versions;
          latestWhere =
            predicate:
            let
              filtered = lib.filterAttrs (version: _: predicate version) versions;
              latest = lib.last (builtins.sort lib.versionOlder (builtins.attrNames filtered));
            in
            filtered.${latest};
        };
      };
  }
) { } files
