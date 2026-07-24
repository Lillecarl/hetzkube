{
  lib,
  buildPythonPackage,
  # dependencies
  hcloud,
  kr8s,
  # build-system
  hatchling,
  hatch-vcs,
}:
buildPythonPackage {
  pname = "cheapam";
  version = (builtins.fromTOML (builtins.readFile ./pyproject.toml)).project.version;
  pyproject = true;

  src = ./.;

  build-system = [
    hatchling
    hatch-vcs
  ];

  dependencies = [
    kr8s
    hcloud
  ];

  pythonImportsCheck = [ "cheapam" ];

  meta = with lib; {
    description = "An IPAM / LARPing CCM for Kubernetes on Hetzner";
    homepage = "https://github.com/lillecarl/hetzkube";
    license = licenses.mit;
    maintainers = with maintainers; [ lillecarl ];
  };
}
