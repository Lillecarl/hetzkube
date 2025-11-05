# Kubernetes on the cheap

NixOS, Hetzner, ClusterAPI

Need help? Hit me up on [Matrix](https://matrix.to/#/@lillecarl:matrix.org)!

# Bootstrapping
## 0.0 Tools
direnv will add the required tools to $PATH for you, it's not an invasive
supermegadirenv like some projects do it for you.
## 0.1  Secrets
Set up new keys in .sops.yaml, you generate keys with "age-keygen". Set up one
for you and one for the node (or share idgaf).

Inspect secrets/all.yaml, it you must set:
hctoken: Hetzner Cloud token
## 1 Local cluster
Use kind or whatever to get a local cluster running, ClusterAPI uses Kubernetes
resources to track cluster state, it'd be stupid for them to implement some
magic bootstrapping store rather than just having a temporary cluster you can
move data into the real one from.
## 2 Init ClusterAPI
Beware of [compatibility](https://github.com/syself/cluster-api-provider-hetzner?tab=readme-ov-file#%EF%B8%8F-compatibility-with-cluster-api-and-kubernetes-versions)!
```bash
clusterctl init \
  --core cluster-api:v1.10.7 \
  --bootstrap kubeadm:v1.10.7 \
  --control-plane kubeadm:v1.10.7 \
  --infrastructure hetzner:v1.0.7
```
## 3 Deploy cluster
Since we don't deploy any loadbalancers you must set a resolveable DNS name on
the cluster address. When you deploy your first controlplane node you must
create the DNS record when the node is being created so everything resolves.
This will later be taken over by external-dns so make sure your domain is on a
external-dns provider host or you can kiss your control-plane goodbye when
you re-roll stuff with ClusterAPI.

```bash
nix run --file . kubenix.deploymentScript --argstr stage capi
```
## 4 Move the CAPI to the cluster
Copy kubeconfig
```bash
clusterctl get kubeconfig hetzkube --namespace hetzkube > hetzkube.kubeconfig
```
Initialize ClusterAPI on the new cluster
```bash
KUBECONFIG=$PWD/hetzkube.kubeconfig clusterctl init \
  --core cluster-api:v1.10.7 \
  --bootstrap kubeadm:v1.10.7 \
  --control-plane kubeadm:v1.10.7 \
  --infrastructure hetzner:v1.0.7
```
Move the cluster
```bash
clusterctl move --to-kubeconfig hetzkube.kubeconfig --namespace hetzkube
```
## 5 Deploy whatever you want bro easykubenix is cool asf

# Discovering
```bash
nix repl --file default.nix
```

# SOPS
Put a decryption key in the image at /etc/nodekey

# kluctl
kluctl sets a label on ALL resources it deploys
```yaml
kluctl.io/discriminator: init
```
If you run reuse the same discriminator for multiple deployments you're in for
a bad time, it'll prune all resources with that label that aren't in the list
of resources you're currently deploying.

hetzkube uses the stage name as the discriminator. kluctl will happily overwrite
the discriminator of your resources so you can "move ownership" easily. But
beware
