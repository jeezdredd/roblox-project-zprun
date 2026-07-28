#!/usr/bin/env python3
"""Upload every manifest entry that has no assetId yet via Roblox Open Cloud.

Reads assets/manifest.json, uploads each pending entry whose file exists,
polls the operation until moderation resolves, and writes the resulting
assetId and status back into the manifest.

Usage:
    python3 scripts/upload_assets.py [--dry-run] [--only PREFIX]

Requires .opencloud.key (git-ignored) containing an Open Cloud API key with
asset read+write scope, and USER_ID below set to the asset owner.
"""

import argparse
import json
import os
import subprocess
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MANIFEST = os.path.join(ROOT, "assets", "manifest.json")
KEY_FILE = os.path.join(ROOT, ".opencloud.key")
USER_ID = "3783240909"

ASSET_ENDPOINT = "https://apis.roblox.com/assets/v1/assets"
OPERATION_ENDPOINT = "https://apis.roblox.com/assets/v1/operations/"

CONTENT_TYPES = {
    ".ogg": "audio/ogg",
    ".mp3": "audio/mpeg",
    ".wav": "audio/wav",
    ".png": "image/png",
    ".jpg": "image/jpeg",
    ".jpeg": "image/jpeg",
}

POLL_ATTEMPTS = 30
POLL_DELAY = 5


def load_key():
    if not os.path.exists(KEY_FILE):
        sys.exit(f"missing {KEY_FILE}")
    with open(KEY_FILE) as handle:
        return handle.read().strip()


def load_manifest():
    with open(MANIFEST) as handle:
        return json.load(handle)


def save_manifest(manifest):
    with open(MANIFEST, "w") as handle:
        json.dump(manifest, handle, indent=2, ensure_ascii=False)
        handle.write("\n")


def asset_type_for(key, path):
    extension = os.path.splitext(path)[1].lower()
    if extension in (".ogg", ".mp3", ".wav"):
        return "Audio"
    if extension in (".png", ".jpg", ".jpeg"):
        return "Image"
    if key.startswith("animation/"):
        return "Animation"
    return None


def curl_json(args):
    result = subprocess.run(args, capture_output=True, text=True)
    if result.returncode != 0:
        return None, result.stderr.strip()
    try:
        return json.loads(result.stdout), None
    except json.JSONDecodeError:
        return None, result.stdout[:300]


def upload(key, name, path, asset_type):
    request = {
        "assetType": asset_type,
        "displayName": name,
        "description": "Task Force Z asset",
        "creationContext": {"creator": {"userId": USER_ID}},
    }
    content_type = CONTENT_TYPES.get(os.path.splitext(path)[1].lower(), "application/octet-stream")
    payload, error = curl_json([
        "curl", "-s", "-X", "POST", ASSET_ENDPOINT,
        "-H", f"x-api-key: {key}",
        "-F", f"request={json.dumps(request)}",
        "-F", f"fileContent=@{path};type={content_type}",
    ])
    if payload is None:
        return None, error
    operation_id = payload.get("operationId")
    if not operation_id:
        return None, json.dumps(payload)[:300]
    return operation_id, None


def poll(key, operation_id):
    for _ in range(POLL_ATTEMPTS):
        payload, error = curl_json(["curl", "-s", OPERATION_ENDPOINT + operation_id, "-H", f"x-api-key: {key}"])
        if payload is None:
            return None, None, error
        if payload.get("done"):
            response = payload.get("response", {})
            state = response.get("moderationResult", {}).get("moderationState", "Unknown")
            return response.get("assetId"), state, None
        time.sleep(POLL_DELAY)
    return None, None, "timed out waiting for moderation"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--dry-run", action="store_true", help="list what would upload and exit")
    parser.add_argument("--only", default="", help="only process keys starting with this prefix")
    arguments = parser.parse_args()

    manifest = load_manifest()
    pending = []
    for key, entry in manifest.items():
        if arguments.only and not key.startswith(arguments.only):
            continue
        if entry.get("assetId"):
            continue
        path = os.path.join(ROOT, entry.get("file", ""))
        if not entry.get("file") or not os.path.exists(path):
            print(f"skip  {key}: file missing ({entry.get('file')})")
            continue
        asset_type = asset_type_for(key, path)
        if asset_type is None:
            print(f"skip  {key}: unsupported extension")
            continue
        pending.append((key, entry, path, asset_type))

    if not pending:
        print("nothing to upload")
        return 0

    if arguments.dry_run:
        for key, _, path, asset_type in pending:
            print(f"would upload {key} ({asset_type}) from {os.path.relpath(path, ROOT)}")
        return 0

    key_value = load_key()
    failures = 0
    for manifest_key, entry, path, asset_type in pending:
        display_name = "tfz-" + manifest_key.replace("/", "-").replace("_", "-")
        operation_id, error = upload(key_value, display_name, path, asset_type)
        if error:
            print(f"FAIL  {manifest_key}: {error}")
            failures += 1
            continue
        asset_id, state, poll_error = poll(key_value, operation_id)
        if poll_error:
            print(f"FAIL  {manifest_key}: {poll_error}")
            failures += 1
            continue
        entry["assetId"] = asset_id or 0
        entry["status"] = (state or "unknown").lower()
        save_manifest(manifest)
        print(f"ok    {manifest_key} -> {asset_id} ({state})")

    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
