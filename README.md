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
     and, if the policy doesn't allow all traffic, a grant letting your devices reach `tag:k8s` on port 443
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
3. Create the Tailscale operator OAuth secret:
   ```
   kubectl create namespace tailscale
   kubectl -n tailscale create secret generic operator-oauth \
     --from-literal=client_id=... --from-literal=client_secret=...
   ```
4. Install Argo CD, then the ApplicationSet that creates one application per directory under `kustomize/`:
   ```
   kubectl kustomize --enable-helm kustomize/argocd | kubectl apply --server-side -f -
   kubectl apply -k kustomize/homelab
   ```
5. Open the Argo CD UI (`kubectl -n argocd port-forward svc/argocd-server 8080:80`, user `admin`, password from
   `kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d`)
   and sync `local-path-provisioner` and `tailscale` first, then the other applications.
   Once `tailscale` is synced, Argo CD is also reachable at `https://argocd.<tailnet>.ts.net`.

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
