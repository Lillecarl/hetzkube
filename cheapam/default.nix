{ writers, kr8s, ... }:
writers.writePython3Bin "cheapam" {
  libraries = [ kr8s ];
  doCheck = false;
} (builtins.readFile ./main.py)
