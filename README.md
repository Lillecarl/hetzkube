# Kubernetes on the cheap

NixOS, Hetzner, ClusterAPI


Beware of [compatibility](https://github.com/syself/cluster-api-provider-hetzner?tab=readme-ov-file#%EF%B8%8F-compatibility-with-cluster-api-and-kubernetes-versions)!
clusterctl init \
  --core cluster-api:v1.10.7 \
  --bootstrap kubeadm:v1.10.7 \
  --control-plane kubeadm:v1.10.7 \
  --infrastructure hetzner:v1.0.7

# Bootstrapping

Since we don't deploy any loadbalancers you must set a hostname on the cluster
address. When you deploy your first controlplane node you must create the DNS
record when the node is being created so everything resolves. This will later
be taken over by external-dns.
