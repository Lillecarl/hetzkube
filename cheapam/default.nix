{
  lib,
  buildPythonPackage,
  fetchFromGitHub,
  # dependencies
  hcloud,
  kr8s,
  # build-system
  hatchling,
  hatch-vcs,
}:
buildPythonPackage rec {
  pname = "cheapam";
  version = "0.1.0";
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
    description = "A Python client library for Kubernetes";
    homepage = "https://github.com/kr8s-org/kr8s";
    license = licenses.mit;
    maintainers = with maintainers; [ lillecarl ];
  };
}
