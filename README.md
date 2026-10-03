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
- [open-iscsi](https://staging--longhornio.netlify.app/docs/0.8.1/deploy/install/#installing-open-iscsi)
- [nfs-common](https://longhorn.io/docs/archives/1.1.0/deploy/install/#installing-nfsv4-client)

A single-node [k3s](https://docs.k3s.io/) cluster is installed,
with the following optional addons disabled:

- helm-controller
- servicelb
- traefik
- local-storage
- metrics-server

## Services

Third-party apps/services:

- [argo-cd](https://argoproj.github.io/cd://argoproj.github.io/cd/)
- [jellyfin](https://jellyfin.org/)
- [metrics-server](https://github.com/kubernetes-sigs/metrics-server)
- [nvidia-device-plugin](https://github.com/NVIDIA/k8s-device-plugin)
- [qbittorrent](https://www.qbittorrent.org/)
- [tailscaled](https://tailscale.com/kb/1185/kubernetes/)

## Tools

- GitOps solution of choice is combination of [kustomize](https://kubectl.docs.kubernetes.io/references/kustomize/) and [argo-cd](https://argo-cd.readthedocs.io/en/stable/)
- Secrets are encrypted using [sops](https://github.com/mozilla/sops) and [ksops](https://github.com/viaduct-ai/kustomize-sops)

## Miscellaneous

### Public & Private services

Public endpoints are served using [Cloudflare Tunnel](https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/), pointing to ingress-nginx.

Private endpoints are served using Tailscale, with each ingress-nginx instance having one tailscale sidecar, giving each of them a private tailscale IP.
One or more A records with the same domain are created that point to these IPs (with the help of cfts-ddns).
This allows any tailscale-connected clients to access these endpoints by resolving the domain through public DNS servers.

