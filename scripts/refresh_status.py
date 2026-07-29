#!/usr/bin/env python3
"""Refresh moderation status for every uploaded asset in the manifest.

Roblox moderates uploads asynchronously, so an asset that returned "Reviewing"
at upload time can later become Approved or Rejected. A rejected asset still has
an id, but loading it fails at runtime with "Asset is not approved for the
requester" — so the manifest has to be corrected or the game spams that error.

    python3 scripts/refresh_status.py            # update assets/manifest.json
    python3 scripts/refresh_status.py --dry-run  # report only

Rejected assets get status "rejected"; sync_configs.py then emits id 0 for them
so consumers stay silent, and sync_needed.py lists them as holes to refill.
"""

import argparse
import json
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MANIFEST = os.path.join(ROOT, "assets", "manifest.json")
KEY_FILE = os.path.join(ROOT, ".opencloud.key")
ASSET_ENDPOINT = "https://apis.roblox.com/assets/v1/assets/"

STATE_TO_STATUS = {
    "Approved": "approved",
    "Rejected": "rejected",
    "Reviewing": "reviewing",
}


def load_key():
    if not os.path.exists(KEY_FILE):
        print(f"missing {KEY_FILE}")
        sys.exit(1)
    with open(KEY_FILE, "r", encoding="utf-8") as handle:
        return handle.read().strip()


def fetch_state(api_key, asset_id):
    result = subprocess.run(
        ["curl", "-s", "-H", f"x-api-key: {api_key}", ASSET_ENDPOINT + str(asset_id)],
        capture_output=True,
        text=True,
    )
    if result.returncode != 0 or not result.stdout.strip():
        return None, "request failed"
    try:
        payload = json.loads(result.stdout)
    except json.JSONDecodeError:
        return None, "bad json"
    moderation = payload.get("moderationResult") or {}
    state = moderation.get("moderationState")
    if state is None:
        return None, payload.get("message", "no moderationState")
    return state, None


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--only", help="only keys starting with this prefix")
    args = parser.parse_args()

    api_key = load_key()
    with open(MANIFEST, "r", encoding="utf-8") as handle:
        manifest = json.load(handle)

    changed = 0
    rejected = []
    for key, entry in sorted(manifest.items()):
        asset_id = str(entry.get("assetId") or "0")
        if asset_id in ("", "0"):
            continue
        if args.only and not key.startswith(args.only):
            continue

        state, error = fetch_state(api_key, asset_id)
        if state is None:
            print(f"skip  {key}: {error}")
            continue

        status = STATE_TO_STATUS.get(state, state.lower())
        if status == "rejected":
            rejected.append(key)
        if entry.get("status") != status:
            print(f"{entry.get('status')} -> {status}  {key}")
            entry["status"] = status
            changed += 1

    if changed and not args.dry_run:
        with open(MANIFEST, "w", encoding="utf-8") as handle:
            json.dump(manifest, handle, indent=2, ensure_ascii=False)
            handle.write("\n")

    print(f"\n{changed} status changes" + (" (dry run, nothing written)" if args.dry_run else ""))
    if rejected:
        print(f"{len(rejected)} rejected assets need replacing: " + ", ".join(rejected))
        print("run scripts/sync_configs.py and scripts/sync_needed.py next")
    return 0


if __name__ == "__main__":
    sys.exit(main())
