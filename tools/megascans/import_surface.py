#!/usr/bin/env python3
"""Import a Quixel Megascans surface from the owner's Fab library as a Roblox
MaterialVariant (docs/environment/megascans.md).

    python3 tools/megascans/import_surface.py <zip or folder> --slot <name>
        [--studs-per-tile N] [--base-material Asphalt|Concrete|Ground|...]
        [--override] [--replaces TFZ_<Set>] [--pattern Regular|Organic]
        [--ao-strength 0.5] [--normal-convention opengl|directx]
        [--source-url URL] [--replace] [--allow-non-square] [--no-sync]

Reads the surface's JSON (name, id, physical size, categories) and its maps by file
name suffix, in the Bridge export layout or the Fab download layout, writes
<slot>_color/normal/roughness[/metalness].png at 1024 px into assets/fab/textures/,
adds pending manifest rows for them, then runs scripts/sync_configs.py and
scripts/sync_needed.py (which also write src/shared/config/MegascansMaterials.luau).
Upload with `python3 scripts/upload_assets.py --only texture/surface/megascans/`, then
sync again: the TFZ_MS_<Slot> variant appears in default.project.json once every map
has an id.

Fab content (Fab Standard License) is never committed, the repository is public:
assets/fab/ is gitignored, the source zip is read in place (a zip is extracted to the
system temp dir and removed) and must not sit inside the repository outside
assets/fab/. A refused import (an uploaded slot without --replace, a clashing variant
name) stops before any map is written; maps are processed in a temp dir and moved into
assets/fab/textures/ only after the manifest is saved.
"""

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, HERE)

import surface as ms  # noqa: E402


def parse_args(argv):
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("source", help="the Megascans zip or extracted folder")
    parser.add_argument("--slot", required=True, help="manifest slot, lower_snake (asphalt_cracked)")
    parser.add_argument("--studs-per-tile", type=float, help="override the size read from the JSON")
    parser.add_argument("--base-material", choices=ms.BASE_MATERIALS, help="guessed from the JSON when left out")
    parser.add_argument("--override", action="store_true", help="make the variant its base material's override")
    parser.add_argument("--replaces", help="an existing set (TFZ_Asphalt) that MaterialUtil.apply should resolve to this one")
    parser.add_argument("--pattern", choices=ms.PATTERNS, default="Regular", help="MaterialPattern (Organic breaks up tiling)")
    parser.add_argument("--ao-strength", type=float, default=0.5, help="how much of the AO map darkens the colour, 0..1")
    parser.add_argument("--normal-convention", choices=("opengl", "directx"), help="force the normal map's convention")
    parser.add_argument("--source-url", dest="source_url", help="the Fab listing URL for the manifest row")
    parser.add_argument("--replace", action="store_true", help="re-import a slot that already has asset ids")
    parser.add_argument("--allow-non-square", action="store_true", help="import maps that are not square (stretched to 1024 x 1024)")
    parser.add_argument("--no-sync", action="store_true", help="do not run the two sync scripts afterwards")
    parser.add_argument("--root", default=REPO, help=argparse.SUPPRESS)
    return parser.parse_args(argv)


def check_source_location(source, root):
    """The source must not sit inside the repository, except under the gitignored
    assets/fab/, so it can never be committed by accident."""
    source = os.path.realpath(source)
    root = os.path.realpath(root)
    fab = os.path.join(root, "assets", "fab")
    inside = source == root or source.startswith(root + os.sep)
    if inside and not (source == fab or source.startswith(fab + os.sep)):
        raise ms.SurfaceError(
            f"{source} is inside the repository; keep Megascans downloads outside it (or under assets/fab/, "
            "which is gitignored)"
        )


def load_manifest(root):
    with open(os.path.join(root, "assets", "manifest.json"), encoding="utf-8") as handle:
        return json.load(handle)


def save_manifest(root, manifest):
    with open(os.path.join(root, "assets", "manifest.json"), "w", encoding="utf-8") as handle:
        json.dump(manifest, handle, indent=2, ensure_ascii=False)
        handle.write("\n")


def known_sets(root):
    """Set names in MaterialUtil.sets, for checking --replaces."""
    path = os.path.join(root, "src", "shared", "util", "MaterialUtil.luau")
    if not os.path.exists(path):
        return None
    with open(path, encoding="utf-8") as handle:
        text = handle.read()
    return set(re.findall(r'name = "(TFZ_[A-Za-z0-9]+)"', text))


def run(argv):
    args = parse_args(argv)
    root = args.root
    slot = ms.check_slot(args.slot)
    check_source_location(args.source, root)
    if args.override and not args.base_material:
        raise ms.SurfaceError("--override changes every part of the base material: name it with --base-material")
    if args.replaces:
        names = known_sets(root)
        if names is not None and args.replaces not in names:
            raise ms.SurfaceError(f"--replaces {args.replaces}: no such set in MaterialUtil.sets")
    # an uploaded slot or a clashing variant name stops here, before any map is touched
    ms.check_import(load_manifest(root), slot, args.replace)

    staging = tempfile.mkdtemp(prefix="megascans-out-")
    try:
        with ms.opened_source(args.source) as folder:
            surface = ms.read_surface(folder)
            base = args.base_material or ms.guess_base_material(surface)
            if not base:
                raise ms.SurfaceError(f"{surface.name}: cannot guess the base material from the JSON; pass --base-material")
            studs = ms.studs_per_tile(surface.metadata, ms.studs_per_metre(root), args.studs_per_tile)
            result = ms.process(surface, staging, slot, base, args.ao_strength, args.normal_convention, args.allow_non_square)

        material = {
            "variant": ms.variant_name(slot),
            "asset": surface.name,
            "baseMaterial": base,
            "studsPerTile": studs,
            "pattern": args.pattern,
            "override": bool(args.override),
        }
        if args.replaces:
            material["replaces"] = args.replaces
        rows = ms.manifest_rows(slot, surface, list(result["files"]), material, args.ao_strength, result["normal"], args.source_url)
        manifest = load_manifest(root)
        removed = ms.apply_rows(manifest, slot, rows, args.replace)
        save_manifest(root, manifest)

        # only now do the maps reach assets/fab/textures (a stale map of the slot goes)
        out_dir = os.path.join(root, ms.FAB_TEXTURES)
        os.makedirs(out_dir, exist_ok=True)
        for suffix in ms.MAP_SUFFIXES_OUT:
            target = os.path.join(out_dir, f"{slot}_{suffix}.png")
            if suffix in result["files"]:
                shutil.move(result["files"][suffix], target)
                result["files"][suffix] = target
            elif os.path.exists(target):
                os.remove(target)
    finally:
        shutil.rmtree(staging, ignore_errors=True)

    convention, how = result["normal"]
    print(f"{surface.name} ({surface.layout} layout) -> {material['variant']} on {base}, {studs} studs per tile")
    print(f"normal: {convention} ({how}){', green flipped' if convention == 'directx' else ''}")
    for path in result["files"].values():
        print(f"wrote {os.path.relpath(path, root)}")
    for key in removed:
        print(f"removed {key}")
    for note in result["notes"]:
        print(f"note: {note}")
    for warning in result["warnings"]:
        print(f"WARNING: {warning}")

    if not args.no_sync:
        for script in ("sync_configs.py", "sync_needed.py"):
            done = subprocess.run([sys.executable, os.path.join(root, "scripts", script)], cwd=root)
            if done.returncode != 0:
                raise ms.SurfaceError(
                    f"the maps and manifest rows are in place, but scripts/{script} failed (its output is above); "
                    f"fix that and run it again before uploading"
                )
    print(f"next: python3 scripts/upload_assets.py --only {ms.MANIFEST_PREFIX}{slot}_ && python3 scripts/sync_configs.py")
    return 0


def main():
    try:
        return run(sys.argv[1:])
    except ms.SurfaceError as error:
        print(f"error: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
