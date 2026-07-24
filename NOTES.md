# Just things that needs to be written down

## Why not use CiliumLoadBalancerIPPool instead of MetalLB?
Cilium sharing doesn't work as well as MetalLB, if ports have names and the names are different Cilium shits itself
MetalLB does exactly what you'd expect with sharing enabled
