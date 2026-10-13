"""Take consistent snapshots of the SQLite databases under /source/config into /snapshots.

Uses SQLite's online backup API, which is safe while the apps are writing. As the first step of a run, it also
sends the healthchecks.io start ping, so the check measures the whole run.
"""
import os
import sqlite3
import sys
import traceback
import urllib.request

SOURCE = "/source/config"
DEST = "/snapshots"


def ping(path, body=None):
    url = os.environ["HEALTHCHECKS_URL"] + path
    try:
        urllib.request.urlopen(url, data=body and body.encode(), timeout=30)
    except Exception as error:  # a missing success ping still raises an alert after the grace time
        print(f"could not ping healthchecks.io: {error}", file=sys.stderr)


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
            print(f"snapshot: {path}", flush=True)
            source_db = sqlite3.connect(f"file:{path}?mode=ro", uri=True)
            dest_db = sqlite3.connect(dest)
            source_db.backup(dest_db)
            dest_db.close()
            source_db.close()


ping("/start")
try:
    main()
except Exception:
    ping("/fail", traceback.format_exc())
    raise
