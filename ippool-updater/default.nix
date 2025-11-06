{ writers, kr8s, ... }:
writers.writePython3Bin "ippool-updater" {
  libraries = [ kr8s ];
  doCheck = false;
} (builtins.readFile ./main.py)
