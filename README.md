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

- smartd (SMART monitoring with a daily short and weekly long self-test), weekly TRIM for the SSD, and a 256M journal limit
- push alerts through [ntfy](https://ntfy.sh) for SMART problems, failed systemd services and disks above 90%
- the NVIDIA driver from Debian's `non-free` (the 550 branch, which still supports Pascal GPUs) and the
  [NVIDIA container toolkit](https://github.com/NVIDIA/nvidia-container-toolkit), which k3s detects as the `nvidia` runtime
- a single-node [k3s](https://docs.k3s.io/) cluster, with the following optional addons disabled:
  - helm-controller
  - servicelb
  - traefik
  - local-storage (replaced by a self-managed local-path-provisioner)
  - metrics-server
- [helm](https://helm.sh/) (through Homebrew), used to render charts when bootstrapping Argo CD

## Services

Third-party apps/services:

- [argo-cd](https://argoproj.github.io/cd/)
- [filebrowser quantum](https://github.com/gtsteffaniak/filebrowser) (web file manager for media, at `https://files.<tailnet>.ts.net`)
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
- `local-bulk`: `/mnt/bulk/k8s` on the HDD, for large app data

Media isn't a PVC: apps mount `/mnt/bulk/media` directly as a `hostPath` volume (see [Media](#media)) and are pinned to `november`
with a `kubernetes.io/hostname` nodeSelector, so they keep running next to the disk if more nodes are added.

### Media

Media lives at `/mnt/bulk/media` on the host, mounted at `/data/media` in jellyfin, qbittorrent and filebrowser as a `hostPath` volume. It's split into one folder per
Jellyfin library. Japanese content has its own libraries because the metadata language is set per library. Documentaries go
under `movies` or `tv` (or their `-jp` counterparts).
The folders are created by the `media` Ansible role, owned by the homelab user (UID 1000, which all apps run as).

| Folder | Jellyfin library | Type | Metadata language / country |
|---|---|---|---|
| `movies` | Movies | Movies | English / US |
| `movies-jp` | Japanese Movies | Movies | Japanese / Japan |
| `tv` | TV Series | Shows | English / US |
| `tv-jp` | Japanese TV Series | Shows | Japanese / Japan |
| `anime` | Anime (series and films) | Shows | Japanese / Japan |

qbittorrent saves to `downloads/`, keeps in-progress torrents in `downloads/incomplete/`, and has one category per library folder
that saves finished torrents straight into it. "Use Category paths in Manual Mode" is enabled, so a relative save path is
resolved against the category's folder.

Jellyfin expects one folder per show, with the TMDB ID to pin the match:

```
tv-jp/孤独のグルメ (2012) [tmdbid-55582]/
├── Season 08/
│   ├── …S08E01….mkv              ← episodes are matched by SxxEyy in the filename
│   ├── …S00E06….mkv              ← specials use season 00, numbered as in TMDB's Specials
│   └── extras/                    ← bonus material, shown as extras
```

Adding a show in qbittorrent:

1. Choose the category (`tv`, `tv-jp` or `anime`), set the torrent to **Manual** mode, and enter the show folder as a **relative**
   save path, e.g. `孤独のグルメ (2012) [tmdbid-55582]` (the ID is in the show's TMDB URL).
2. In the torrent's **Content** tab, rename the release folder to `Season NN`, and rename or move extras and specials
   (`extras/…`, `…S00Exx…`). qbittorrent renames them on disk and keeps seeding.
3. To change a save path later, use **Set location** on the torrent so qbittorrent moves the files and keeps seeding.
   Renaming or moving files outside qbittorrent leaves the torrent with missing files (fixable with Set location and a recheck).

Films can stay in **Automatic** mode: each release folder in `movies` or `movies-jp` is matched as one film.

Playback languages are per user: preferred audio language English, "Play default audio track regardless of language" on, and
subtitle mode Smart with English subtitles, so Japanese audio plays with English subtitles and English audio without.

In Jellyfin's transcoding settings, hardware acceleration is NVIDIA NVENC, and **Throttle transcodes** and **Delete segments** are
enabled so transcodes fit in the 6Gi RAM volume. Hardware decoding is enabled for what the GTX 1050 Ti's NVDEC supports
([NVIDIA support matrix](https://developer.nvidia.com/video-encode-decode-support-matrix)): H264, HEVC, HEVC 10bit, MPEG2, MPEG4,
VC1 and VP9. VP8, VP9 10bit, HEVC RExt and AV1 stay off (VP9 10bit is listed as unsupported for one 1050 Ti revision); those
formats are decoded on the CPU. HEVC encoding is allowed.

### Alerts

Push notifications go to an [ntfy](https://ntfy.sh) topic through `/usr/local/bin/homelab-notify <title> <message> [priority] [tags]`:

- smartd runs `/usr/local/bin/smartd-ntfy` for SMART problems (priority 5)
- `homelab-diskspace.timer` checks `/`, `/mnt/fast` and `/mnt/bulk` daily at 09:00 and warns above 90%
- any systemd unit with `OnFailure=homelab-notify-failure@%n.service` sends an alert with the end of its log when it fails

The topic lives only on the host (`/etc/homelab/ntfy.env`, root-only), since anyone who knows it can read the alerts;
`site.yaml` prompts for it when it's missing. Send a test with `sudo homelab-notify "Test" "Hello"`.

### Remote kubectl

The Tailscale operator runs an [API server proxy](https://tailscale.com/docs/kubernetes-operator/api-server-access) in auth mode.
Requests are authenticated with the caller's Tailscale identity and mapped to Kubernetes groups by the policy grant above,
so no Kubernetes credentials leave the host. From any tailnet device with `kubectl` installed:

```
tailscale configure kubeconfig tailscale-operator
```

On a machine without the `tailscale` CLI, such as WSL with Tailscale running on Windows, create the same kubeconfig by hand.
The token is a placeholder; the proxy authenticates the connection's Tailscale identity instead:

```
kubectl config set-cluster homelab --server=https://tailscale-operator.<tailnet>.ts.net
kubectl config set-credentials tailscale-auth --token=unused
kubectl config set-context homelab --cluster=homelab --user=tailscale-auth
kubectl config use-context homelab
```

If WSL can't resolve or reach tailnet names, enable `networkingMode=mirrored` and `dnsTunneling=true` under `[wsl2]` in
`%USERPROFILE%\.wslconfig`, then run `wsl --shutdown`.

The first request after the operator starts may time out while the proxy gets its certificate.
If the cluster can't run pods, the proxy is unavailable too; SSH to the host and use its local kubeconfig instead.
