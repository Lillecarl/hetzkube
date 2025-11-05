{
  lib,
  buildPythonPackage,
  fetchFromGitHub,
  # dependencies
  cachetools,
  cryptography,
  exceptiongroup,
  packaging,
  pyyaml,
  python-jsonpath,
  anyio,
  httpx,
  httpx-ws,
  python-box,
  # build-system
  hatchling,
  hatch-vcs,
}:
buildPythonPackage rec {
  pname = "kr8s";
  version = "0.20.13";
  pyproject = true;

  src = fetchFromGitHub {
    owner = "kr8s-org";
    repo = "kr8s";
    tag = "v${version}";
    hash = "sha256-9fo18ririQwBzxuPp8+oH20URv0nvXCkv0eIUL4xrZ8=";
  };

  build-system = [
    hatchling
    hatch-vcs
  ];

  dependencies = [
    cachetools
    cryptography
    exceptiongroup
    packaging
    pyyaml
    python-jsonpath
    anyio
    httpx
    httpx-ws
    python-box
  ];

  pythonImportsCheck = [ "kr8s" ];

  meta = with lib; {
    description = "A Python client library for Kubernetes";
    homepage = "https://github.com/kr8s-org/kr8s";
    license = licenses.mit;
    maintainers = with maintainers; [ lillecarl ];
  };
}
