# Just things that needs to be written down

## Why not use CiliumLoadBalancerIPPool instead of MetalLB?
https://docs.cilium.io/en/stable/network/lb-ipam/#sharing-keys
It's more annoying to share IP's using Ciliums feature, and I haven't tested it.
MetalLB works, it will reassign IP's when they're removed from a pool which is
essential since IP's live with the nodes. MetalLB only does the IP assignment.
