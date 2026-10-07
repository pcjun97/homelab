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
- 128GB SSD
- 512GB HDD + 1TB HDD (LVM)
- Nvidia 1050Ti

## Platform

The operating system of choice is Debian 11 (bullseye), with the following packages installed:

- [tailscale](https://tailscale.com/kb/1031/install-linux/)
- [nvidia-container-toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/install-guide.html#step-2-install-nvidia-container-toolkit)

A single-node [k3s](https://docs.k3s.io/) cluster is installed,
with the following optional addons disabled:

- helm-controller
- servicelb
- traefik
- local-storage (replaced by a self-managed local-path-provisioner)
- metrics-server

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
- No secrets are stored in git. The Tailscale operator OAuth secret is created by hand before syncing:
  `kubectl create namespace tailscale && kubectl -n tailscale create secret generic operator-oauth --from-literal=client_id=... --from-literal=client_secret=...`

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
