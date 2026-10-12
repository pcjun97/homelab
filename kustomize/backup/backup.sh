#!/bin/sh
# Sync the SQLite snapshots, the app config volumes and the media library to Backblaze B2.
set -eu -o pipefail

notify() {
  wget -q -O /dev/null \
    --header "Title: [november] backup failed" \
    --header "Priority: 5" \
    --header "Tags: rotating_light" \
    --post-data "$1" \
    "https://ntfy.sh/${NTFY_TOPIC}" || echo "could not send ntfy alert" >&2
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
  notify "$(tail -c 3500 /tmp/backup.log)"
  exit 1
fi
echo "backup complete"
