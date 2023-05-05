# Chi Jun's Homelab

This project stores configurations of services in my homelab.

## TODO

- Add more nodes for a high-availability setup
- Enable longhorn's replication
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

## Services

Third-party apps/services:

- argo-cd
- cert-manager
- cloudflared
- firefly-iii
- grafana
- httpbin
- ingress-nginx
- jellyfin
- kube-state-metrics
- loki
- longhorn
- metrics-server
- minio
- nvidia-device-plugin
- prometheus
- promtail
- qbittorrent
- syncthing
- tailscale

Self-developed apps/services:

- cfts-ddns

## Tools

- GitOps solution of choice is combination of [kustomize](https://kubectl.docs.kubernetes.io/references/kustomize/) and [argo-cd](https://argo-cd.readthedocs.io/en/stable/)
- Secrets are encrypted using [sops](https://github.com/mozilla/sops) and [ksops](https://github.com/viaduct-ai/kustomize-sops)

## Miscellaneous

### Public & Private services

Public endpoints are served using cloudflared.

Private endpoints are served using Tailscale, with each ingress-nginx instance having one tailscale sidecar, giving each of them a private tailscale IP.
One or more A records with the same domain are created that point to these IPs (with the help of cfts-ddns).
This allows any tailscale-connected clients to access these endpoints by resolving the domain through public DNS servers.

