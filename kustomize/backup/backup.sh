#!/bin/sh
# Sync the SQLite snapshots, the app config volumes and the media library to Backblaze B2.
set -eu -o pipefail

# Report to the healthchecks.io check (it alerts through ntfy). A failed ping only loses the report:
# a missing success ping still raises an alert once the grace time runs out.
ping() {
  for _ in 1 2 3; do
    wget -q -T 30 -O /dev/null --post-data "${2:-}" "${HEALTHCHECKS_URL}$1" && return 0
    sleep 10
  done
  echo "could not ping healthchecks.io" >&2
}

rclone_sync() {
  rclone sync "$@" \
    --bwlimit "${BWLIMIT}" \
    --max-delete "${MAX_DELETE}" \
    --fast-list \
    --transfers 4 \
    --log-level INFO \
    --stats 10m \
    --stats-log-level NOTICE
}

# Chained with && because set -e doesn't apply inside the `if` below: the first failure stops the run
# and becomes the function's exit status.
backup() {
  rclone_sync /snapshots "b2:${BUCKET}/sqlite" &&
  # Live SQLite files are excluded; the consistent snapshots are uploaded above
  rclone_sync /source/config "b2:${BUCKET}/config" \
    --exclude '*.db' --exclude '*.db-wal' --exclude '*.db-shm' \
    --exclude '*.sqlite' --exclude '*.sqlite-wal' --exclude '*.sqlite-shm' \
    --exclude '*-journal' &&
  rclone_sync /source/media "b2:${BUCKET}/media" \
    --exclude 'downloads/incomplete/**'
}

if ! backup 2>&1 | tee /tmp/backup.log; then
  ping /fail "$(tail -c 10000 /tmp/backup.log)"
  exit 1
fi
ping ""
echo "backup complete"
