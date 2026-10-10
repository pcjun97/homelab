"""Take consistent snapshots of the SQLite databases under /source/config into /snapshots.

Uses SQLite's online backup API, which is safe while the apps are writing.
"""
import os
import sqlite3
import sys
import traceback
import urllib.request

SOURCE = "/source/config"
DEST = "/snapshots"


def notify(message):
    request = urllib.request.Request(
        f"https://ntfy.sh/{os.environ['NTFY_TOPIC']}",
        data=message[-3500:].encode(),
        headers={"Title": "[november] backup failed (snapshots)", "Priority": "5", "Tags": "rotating_light"},
    )
    try:
        urllib.request.urlopen(request, timeout=30)
    except Exception as error:  # the job still fails; this only loses the alert
        print(f"could not send ntfy alert: {error}", file=sys.stderr)


def main():
    for root, _, files in os.walk(SOURCE):
        for name in files:
            if not name.endswith((".db", ".sqlite")):
                continue
            path = os.path.join(root, name)
            with open(path, "rb") as file:
                if file.read(15) != b"SQLite format 3":
                    continue
            dest = os.path.join(DEST, os.path.relpath(path, SOURCE))
            os.makedirs(os.path.dirname(dest), exist_ok=True)
            source_db = sqlite3.connect(f"file:{path}?mode=ro", uri=True)
            dest_db = sqlite3.connect(dest)
            source_db.backup(dest_db)
            dest_db.close()
            source_db.close()
            print(f"snapshot: {path}")


try:
    main()
except Exception:
    notify(traceback.format_exc())
    raise
