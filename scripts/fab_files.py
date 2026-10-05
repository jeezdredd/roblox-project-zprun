"""Rules for manifest rows that point at Fab content (Fab Standard License).

The repository is public and the Fab EULA does not allow making Fab content available
outside the shipped game, so no Fab-derived file is committed: they live under
assets/fab/ (gitignored) on the owner's machine only. The manifest rows (ids, licence,
note) are committed; in any other clone their files are missing, which is accepted
once the row has an asset id, and a row without one fails the pre-commit check.
Used by sync_configs.py and upload_assets.py.
"""

import os

FAB_PREFIX = "assets/fab/"


def is_fab_licence(entry):
    return (entry.get("license") or "").startswith("Fab ")


def is_fab_file(entry):
    return (entry.get("file") or "").startswith(FAB_PREFIX)


def has_id(entry):
    return bool(entry.get("assetId"))


def problems(manifest, root, require_ids=False):
    """Fab rows that break the rules, as "key: why" lines. With require_ids (the
    pre-commit --check) every Fab row must have its asset id, file or not: no other
    clone can upload it, so a pending row must never be committed."""
    out = []
    for key, entry in sorted(manifest.items()):
        if is_fab_licence(entry) and not is_fab_file(entry):
            out.append(f"{key}: Fab content must live under {FAB_PREFIX} (gitignored), not {entry.get('file')}")
            continue
        if not is_fab_file(entry) or has_id(entry):
            continue
        if require_ids:
            out.append(f"{key}: no asset id; upload it on the owner's machine before committing (no other clone can)")
        elif not os.path.exists(os.path.join(root, entry["file"])):
            out.append(
                f"{key}: no asset id and {entry['file']} is missing; Fab files exist only on the "
                "owner's machine, so upload the row there before committing it"
            )
    return out
