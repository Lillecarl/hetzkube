rec {
  default = import ./. { stage = "full"; };
  kc = default.kubenix.eval.config;
}
