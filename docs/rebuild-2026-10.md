# Homelab rebuild (October 2026)

Notes and decisions from planning the rebuild of `november`, the single homelab server.

## Background

- One disk failed. With Longhorn running on top of LVM across several disks, the data couldn't
  realistically be recovered, so everything is starting from scratch.
- Prometheus and Home Assistant wrote to disk heavily, with Longhorn adding write amplification on top.
  This is the suspected cause of a dead SSD.
- The age private key used by sops was lost along with the cluster, which held it as the `ksops-age`
  secret. None of the old `*.enc.yaml` files can be decrypted.

## Host state at the start of the rebuild

- Debian 13 (trixie), fresh install. Only `tailscale` and `git` are installed.
- i5-3330, 16GB RAM, GTX 1050 Ti. No swap.
- Disks:
  - `sdb` Kingston A400 960GB SSD: EFI, `/boot`, `/` (200G), `/mnt/fast` (693G).
    A budget, DRAM-less SSD, rated for roughly 300TBW.
  - `sda` WD Blue 1TB HDD: `/mnt/bulk` (916G).
  - Plain ext4. No LVM, no RAID.
- The SATA controller is in IDE mode in the BIOS. It should be switched to AHCI.

## Decisions

| Topic | Decision | Reason |
|---|---|---|
| Platform | Keep k3s + Argo CD | Learning, and a possible future multi-node setup |
| Dropped apps | longhorn, prometheus, grafana, kube-state-metrics, home-assistant, mosquitto, reflector | Write load and SSD wear, complexity, or no longer used |
| Ingress | Drop ingress-nginx; use the Tailscale operator's `tailscale` ingress class | ingress-nginx was retired in March 2026. Each service gets `https://<name>.<tailnet>.ts.net` |
| Domain | Give up `chijun.website`, which also drops cert-manager and external-dns. Use full `*.<tailnet>.ts.net` names with bookmarks | Nothing needs access without Tailscale. Short MagicDNS names can't have valid HTTPS (certificates cover only the full ts.net name; the operator's `tailscale.com/http-redirect` keeps the typed host). Keeping a custom domain would need a Gateway API proxy (Envoy Gateway or Traefik) behind a Tailscale LoadBalancer, plus cert-manager with a Cloudflare token and a wildcard DNS record; not worth it for a few apps |
| Storage | Run local-path-provisioner through Argo (k3s `--disable local-storage`). Two StorageClasses: `local-fast` → `/mnt/fast`, `local-bulk` → `/mnt/bulk`. `reclaimPolicy: Retain`; `pathPattern` `{{ .PVC.Namespace }}/{{ .PVC.Name }}` so folder names stay the same across rebuilds | One node, so Longhorn added risk without adding redundancy. Running it ourselves keeps its config and upgrades in git (k3s rewrites the bundled copy's config on restart) and maps each class to its own disk. Stable folder names let restored backups be found |
| File manager | FileBrowser Quantum, behind the Tailscale ingress, mounting the media PVC | Works most like a desktop file explorer. No need for SFTP; host SSH covers protocol access. The original FileBrowser was archived in 2026-09; copyparty was considered (more popular, plainer UI). Known issue: slow on folders with ~10k subfolders |
| `media-storage` pod | Drop it; SSH/SFTP to the host directly | Media is a host folder and the host is on the tailnet |
| Secrets | Drop sops/ksops. The only secret, the Tailscale operator OAuth client, is created by `ansible/bootstrap.yaml` from a hidden prompt (never in git, shell history or process arguments) | It's the only secret left; removes the fragile Argo repo-server plugin setup |
| Argo sync | Keep manual sync; no automated sync, prune or selfHeal | User preference |
| Dependency updates | Renovate: automerge patch and minor updates once CI passes; majors wait for approval in the Dependency Dashboard; runs weekly (weekend). CI (GitHub Actions) renders every app with `kustomize build --enable-helm` and runs `ansible-lint`. Done after the MVP | Renovate PRs were never reviewed, so the cluster ran year-old versions. Merging only changes git; with manual Argo sync, the OutOfSync diff in Argo becomes the review step |
| Host setup | Ansible, kept in this repo: `site.yaml` sets up the host (with sudo), `bootstrap.yaml` sets up the cluster (no sudo). Ansible comes from apt (`ansible`, which bundles `community.general`); CLI tools such as helm come from Homebrew | Idempotent, can be re-run; turns a rebuild into "run playbooks + restore" |
| Bootstrap syncs | `bootstrap.yaml` syncs `local-path-provisioner`, `tailscale`, `metrics-server`, `argocd` and `homelab` once, only if they've never been synced; everything after that is synced by hand. Syncs use server-side apply | Gets a fresh cluster to a working state in one command without giving up manual sync. Argo CD's CRDs are too large for client-side apply |
| Tailscale tags | The operator's defaults: `tag:k8s-operator` (operator, hostname `tailscale-operator`) and `tag:k8s` (ingress devices) | One cluster on the tailnet, so a `homelab-k3s-` prefix added nothing; the defaults match Tailscale's docs |
| Remote kubectl | The operator's API server proxy in auth mode; a policy grant gives `autogroup:admin` `system:masters`. From WSL (Tailscale runs on Windows), build the kubeconfig by hand pointing at `https://tailscale-operator.tailbc93b.ts.net` with a placeholder token | No Kubernetes credentials leave the host; access is revoked in the Tailscale policy |
| PR workflow | Small PRs based on `main`, squash-merged. Stack only when a PR depends on another, and rebase onto `main` after the lower one merges. Nothing is applied or run until its PR is open and reviewed | Easier review; squash merges leave stacked branches with duplicate commits |
| Backups | Configs and media both go offsite to **Backblaze B2**; migrate to a Hetzner Storage Box if B2 costs more than expected | The lesson from this failure. B2: nicer UX, bucket-scoped keys, charged on what you store |
| Backup tool | `rclone sync` from the host (systemd timer installed by Ansible) of `/mnt/fast` and `/mnt/bulk` to B2. The bucket lifecycle keeps old file versions for 30 days. No encryption, no Object Lock | Simplest option: files stay plain and browsable in B2. Versions cover accidental deletion, a bad upgrade, and a failing disk uploading corrupted files. Locks only protect against an attacker; low risk with Tailscale-only access. kopia/restic were considered: little benefit for media that doesn't dedupe |
| Alerts | **healthchecks.io**: a backup-job check (pings on start, success and failure; alerts on failure or a missing ping) and a **heartbeat** check (a systemd timer pings every 5 min; grace 15 min; sends down and up alerts). **ntfy.sh** push (long random topic) for `smartd` problems and disk space above 90% on `/mnt/fast` and `/mnt/bulk`. healthchecks.io forwards to the same ntfy topic | A dead server can't report itself, so an outside check is needed; the heartbeat catches a dead or offline host within ~20 min instead of a day. Silence when healthy; everything arrives as phone push. Telegram and email were considered |

## Open items

- **Backup cost notes** (2026-10-03, at USD 1 = RM4.08 and EUR 1 = RM4.61; prices exclude VAT/SST):
  - B2: $6.95/TB/month (since 2026-05), which is RM28.36/TB
  - Hetzner Storage Box: 1TB €3.20 (RM14.75), 5TB €10.90 (RM50.25), 10TB €20.80 (RM95.89), 20TB €40.60 (RM187.17)
  - At about 1TB B2 costs about RM11–14/month more. B2 is cheaper from 1TB to about 1.8TB, where Hetzner jumps
    to the 5TB box. Above 2TB, Hetzner is much cheaper. To migrate, use `rclone copy` between the providers.
- **Jellyfin's SQLite database:** rclone copies files while they're in use, so a live database can be copied
  half-written. Either stop Jellyfin briefly during the config sync, or copy a database backup file instead.
  Decide when writing the backup job.

## Other improvements discussed

- **SSD wear:**
  - Cap container log and journald sizes.
  - Enable `fstrim.timer` and switch the SATA controller to AHCI.
- **Jellyfin fonts:** the CJK font init container runs `apt install` on every start; consider replacing it.
- **Tailscale key expiry:** turn it off for the host node `november`.

## Progress

### Done (on `main`)

- [x] Dropped apps removed (#145); Tailscale ingress for argocd, jellyfin and qbittorrent (#149)
- [x] sops/ksops and all encrypted secrets removed; `media-storage` sidecar removed (#152)
- [x] `local-path-provisioner` (pinned `v0.0.37`) with `local-fast` (default, `/mnt/fast/k8s`) and `local-bulk` (`/mnt/bulk/k8s`),
      both `Retain`, folders `<namespace>/<pvc>/`; shared `media` PVC replaces `media-storage` (#153)
- [x] Platform charts bumped: argo-cd 10.9.6, tailscale-operator 1.102.4, metrics-server 3.14.0, nvidia-device-plugin 0.20.1 (#156)
- [x] Ansible `site.yaml`: k3s v1.36.5+k3s1 (traefik, servicelb, local-storage, metrics-server, helm-controller disabled),
      storage folders, kubeconfig, `KUBECONFIG` in `~/.bashrc`, helm via Homebrew (#157, #158)
- [x] Default Tailscale tags and hostname (#159); API server proxy (#160)
- [x] Ansible `bootstrap.yaml`: OAuth secret prompt, Argo CD, ApplicationSet, first syncs (#161)
- [x] **MVP running (2026-10-10):** local-path-provisioner, tailscale, metrics-server, argocd and homelab are Synced and Healthy;
      Argo CD at `https://argocd.tailbc93b.ts.net`
- [x] Tailscale admin console: MagicDNS and HTTPS on, default tags in `tagOwners`, OAuth client with Devices Core, Auth Keys and Services

### Lessons from the MVP bring-up

- k3s's bundled `kubectl` ignores `~/.kube/config` unless `KUBECONFIG` is set (fixed in #158).
- The ingress devices need **HTTPS certificates** enabled for the tailnet; check `tailscale status --json` shows `CertDomains`.
- If ingresses get no address, check the operator logs: `requested tags [tag:k8s] are invalid or not permitted` means
  `tagOwners` doesn't let `tag:k8s-operator` own `tag:k8s`. The operator recovers by itself once the policy is fixed.

### To do

- [ ] Argo CD: change the `admin` password and delete `argocd-initial-admin-secret`
- [ ] Apps: NVIDIA driver and container toolkit in Ansible (Debian's 550 driver, since NVIDIA's Debian 13 repository ships 590+,
      which dropped Pascal); sync `nvidia`, `media`, jellyfin and qbittorrent
- [ ] App updates: jellyfin 12.1 and qbittorrent 5.2.4 images; `PUID`/`PGID=1000`; jellyfin transcodes on a 4Gi RAM-backed emptyDir
      at `/config/cache/transcodes` (then set the transcode path in Dashboard → Playback → Transcoding).
      qbittorrent 5.x prints a temporary WebUI password in its logs on first start
- [ ] FileBrowser Quantum `1.5.6-stable` at `files.tailbc93b.ts.net`, mounting `media`, data on `local-fast`
      (change the default `admin`/`admin` password on first login)
- [ ] CI workflow (render all apps, ansible-lint) as a required check
- [ ] Renovate config (automerge patch/minor, majors via Dependency Dashboard approval, weekly schedule,
      custom rule for the k3s version in Ansible, versioning rule for linuxserver tags); clean up the stale `renovate/*` branches
- [ ] Ansible: smartd, `fstrim.timer`, journald and container log limits
- [ ] Create the B2 bucket (lifecycle: keep prior versions 30 days) and a bucket-scoped application key
- [ ] rclone backup job: Ansible role + systemd timer
- [ ] Alerts: create the ntfy topic and the healthchecks.io checks (backup + heartbeat, forwarding to ntfy); Ansible sets up smartd
      (alerts through ntfy), a daily disk-space check, healthchecks pings in the backup job, and the heartbeat timer
- [ ] Optional: keep the Tailscale policy file in the repo and sync it with Tailscale's GitHub Action
- [ ] Turn off Tailscale key expiry for `november`; switch the SATA controller to AHCI in the BIOS
