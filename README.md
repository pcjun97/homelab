# Chi Jun's Homelab

This project stores configurations of services in my homelab.

## TODO

- Add more nodes for a high-availability setup
- Implement solution for backup to offsite storage
- Include IaC (Infrastructure as Code) for server setup (OS & packages)
- Add and improve documentations
- Add CI/CD to lint and sync the configurations

## Hardware

The homelab runs on a single machine with the following specifications:

- Intel i5-3330
- 16GB RAM (8GB+8GB)
- 960GB SSD (OS + `/mnt/fast`)
- 1TB HDD (`/mnt/bulk`)
- Nvidia 1050Ti

## Platform

The operating system of choice is Debian 13 (trixie), with [tailscale](https://tailscale.com/kb/1031/install-linux/) installed.

The rest of the host is set up with Ansible (`ansible/`), which installs:

- a single-node [k3s](https://docs.k3s.io/) cluster, with the following optional addons disabled:
  - helm-controller
  - servicelb
  - traefik
  - local-storage (replaced by a self-managed local-path-provisioner)
  - metrics-server
- [helm](https://helm.sh/) (through Homebrew), used to render charts when bootstrapping Argo CD

## Services

Third-party apps/services:

- [argo-cd](https://argoproj.github.io/cd://argoproj.github.io/cd/)
- [jellyfin](https://jellyfin.org/)
- [local-path-provisioner](https://github.com/rancher/local-path-provisioner)
- [metrics-server](https://github.com/kubernetes-sigs/metrics-server)
- [nvidia-device-plugin](https://github.com/NVIDIA/k8s-device-plugin)
- [qbittorrent](https://www.qbittorrent.org/)
- [tailscaled](https://tailscale.com/kb/1185/kubernetes/)

## Tools

- GitOps solution of choice is combination of [kustomize](https://kubectl.docs.kubernetes.io/references/kustomize/) and [argo-cd](https://argo-cd.readthedocs.io/en/stable/)
- No secrets are stored in git. The Tailscale operator OAuth secret is created by hand (see [Bootstrap](#bootstrap)).

## Bootstrap

1. In the Tailscale admin console:
   - Enable MagicDNS and HTTPS certificates
   - Add the operator's default tags to the policy file:
     ```jsonc
     "tagOwners": {
       "tag:k8s-operator": [],
       "tag:k8s": ["tag:k8s-operator"],
     },
     ```
     and, if the policy doesn't allow all traffic, a grant letting your devices reach `tag:k8s` and `tag:k8s-operator` on port 443
   - Give tailnet admins cluster-admin through the operator's API server proxy:
     ```jsonc
     "grants": [{
       "src": ["autogroup:admin"],
       "dst": ["tag:k8s-operator"],
       "app": { "tailscale.com/cap/kubernetes": [{ "impersonate": { "groups": ["system:masters"] } }] },
     }],
     ```
   - Create an OAuth client (Settings → Trust credentials) tagged `tag:k8s-operator`, with write access to
     Devices Core, Auth Keys and Services, as in the
     [operator install guide](https://tailscale.com/docs/kubernetes-operator/install-operator)
2. Set up the host. This needs Ansible and [Homebrew](https://brew.sh) installed on the host first.
   Debian's `ansible` package includes the `community.general` collection; with plain `ansible-core`,
   run `ansible-galaxy collection install -r requirements.yaml` as well.
   Add `--connection=local` when running on the host itself:
   ```
   sudo apt install ansible
   cd ansible && ansible-playbook site.yaml --ask-become-pass
   ```
3. Bootstrap the cluster from the host (no sudo needed; `kubectl` and `helm` must be on the `PATH`):
   ```
   cd ansible && ansible-playbook bootstrap.yaml
   ```
   The playbook skips any step that's already done:
   - prompts for the Tailscale OAuth client ID and secret (the secret is hidden and never logged)
     and creates the `operator-oauth` secret
   - installs Argo CD and the ApplicationSet, which creates one application per directory under `kustomize/`
   - syncs `local-path-provisioner`, `tailscale`, `metrics-server`, `argocd` and `homelab` in order, waiting for each to
     become healthy. Only applications that have never been synced are synced, so re-running it never forces a sync.
4. Sync the remaining applications by hand in Argo CD, at `https://argocd.<tailnet>.ts.net`
   (user `admin`, password from
   `kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d`).

## Miscellaneous

### Networking

All endpoints are private and only reachable over Tailscale.
Each `Ingress` uses the `tailscale` ingress class from the Tailscale operator,
which gives the service its own tailnet device at `https://<name>.<tailnet>.ts.net` with a certificate issued by Tailscale.
MagicDNS and HTTPS must be enabled for the tailnet.

### Storage

Volumes are provisioned by local-path-provisioner into `<disk>/k8s/<namespace>/<pvc>/`, with `reclaimPolicy: Retain`:

- `local-fast` (default): `/mnt/fast` on the SSD, for app config
- `local-bulk`: `/mnt/bulk` on the HDD, for media (the `media` PVC shared by jellyfin and qbittorrent)

### Remote kubectl

The Tailscale operator runs an [API server proxy](https://tailscale.com/docs/kubernetes-operator/api-server-access) in auth mode.
Requests are authenticated with the caller's Tailscale identity and mapped to Kubernetes groups by the policy grant above,
so no Kubernetes credentials leave the host. From any tailnet device with `kubectl` installed:

```
tailscale configure kubeconfig tailscale-operator
```

If the cluster can't run pods, the proxy is unavailable too; SSH to the host and use its local kubeconfig instead.
